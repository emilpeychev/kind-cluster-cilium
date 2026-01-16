#!/usr/bin/env bash
set -euo pipefail
# 09-argo-events.sh - Install Argo Events with GitHub polling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 9: Install Argo Events"

require_cmd helm

cd "$ROOT_DIR"

# Add /etc/hosts entry
grep -q "webhooks.local" /etc/hosts || echo "$METALLB_IP webhooks.local" | sudo tee -a /etc/hosts

# Install Argo Events via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argo-events argo/argo-events -n argo-events --create-namespace -f ArgoCD-Events/values.yaml 2>/dev/null || \
  helm upgrade argo-events argo/argo-events -n argo-events -f ArgoCD-Events/values.yaml

# Wait for Argo Events components to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argo-events-controller-manager -n argo-events

# Create argo-events-sa service account for sensors
kubectl create sa argo-events-sa -n argo-events 2>/dev/null || true

# Create GitHub webhook secret
kubectl create secret generic github-webhook-secret \
  --from-literal=secret="my-github-webhook-secret-token" \
  -n argo-events \
  --dry-run=client -o yaml | kubectl apply -f -

# Create RBAC for Argo Events sensor to create Tekton PipelineRuns
kubectl apply -f ArgoCD-Events/rbac.yaml

# Create role and binding for argo-events-sa to create PipelineRuns in tekton-builds
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-events-pipelinerun-creator
  namespace: tekton-builds
rules:
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns"]
    verbs: ["create", "get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-events-sa-pipelinerun-binding
  namespace: tekton-builds
subjects:
  - kind: ServiceAccount
    name: argo-events-sa
    namespace: argo-events
roleRef:
  kind: Role
  name: argo-events-pipelinerun-creator
  apiGroup: rbac.authorization.k8s.io
EOF

# Apply Argo Events resources (EventBus first, then EventSource, then Sensor)
kubectl apply -n argo-events -f ArgoCD-Events/jetstream-ventbus.yaml
log "Waiting for EventBus JetStream to be ready..."
sleep 30
kubectl wait --for=condition=Deployed eventbus/default -n argo-events --timeout=120s || echo "EventBus may still be starting..."

# Apply webhook-poll eventsource and sensor (for polling-based triggers)
kubectl apply -n argo-events -f ArgoCD-Events/webhook-poll-eventsource.yaml
kubectl apply -n argo-events -f ArgoCD-Events/webhook-poll-sensor.yaml

# Apply GitHub webhook eventsource and sensor (for direct webhook triggers)
kubectl apply -n argo-events -f ArgoCD-Events/github-webhook-eventsource.yaml
kubectl apply -n argo-events -f ArgoCD-Events/webhook-httproute.yaml
kubectl apply -n argo-events -f ArgoCD-Events/github-sensor-debug.yaml

# Apply CronJob for GitHub polling
kubectl apply -f Tekton-Pipelines/tekton-trigger-cronjob.yaml

log "Waiting for Argo Events pods to be ready..."
sleep 10
kubectl wait --for=condition=Ready pod -l eventsource-name=github -n argo-events --timeout=120s || echo "EventSource pod may still be starting..."
kubectl wait --for=condition=Ready pod -l eventsource-name=webhook-poll -n argo-events --timeout=120s || echo "Poll EventSource may still be starting..."

log "Argo Events installed successfully"
echo "Webhook endpoint: https://webhooks.local/github"
echo "Poll trigger: CronJob polls GitHub every minute and triggers via Argo Events"
