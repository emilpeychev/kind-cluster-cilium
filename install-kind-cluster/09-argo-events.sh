#!/usr/bin/env bash
set -euo pipefail
# 09-argo-events.sh - Install Argo Events with GitHub webhooks

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
helm upgrade --install argo-events argo/argo-events -n argo-events --create-namespace -f ArgoCD-Events/values.yaml

# Wait for Argo Events components to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argo-events-controller-manager -n argo-events

# Create argo-events-sa service account and webhook secret from manifests
kubectl apply -f ArgoCD-Events/serviceaccount.yaml
kubectl apply -f ArgoCD-Events/github-webhook-secret.yaml

# Create RBAC for Argo Events sensor to create Tekton PipelineRuns
kubectl apply -f ArgoCD-Events/rbac.yaml

# Apply Argo Events resources (EventBus first, then EventSource, then Sensor)
kubectl apply -n argo-events -f ArgoCD-Events/jetstream-eventbus.yaml
log "Waiting for EventBus JetStream to be ready..."
sleep 30
kubectl wait --for=condition=Deployed eventbus/default -n argo-events --timeout=120s || echo "EventBus may still be starting..."


# Apply GitHub webhook eventsource and sensor (for direct webhook triggers)
kubectl apply -n argo-events -f ArgoCD-Events/github-webhook-eventsource.yaml
kubectl apply -n argo-events -f ArgoCD-Events/webhook-httproute.yaml
kubectl apply -n argo-events -f ArgoCD-Events/github-sensor-debug.yaml


log "Waiting for Argo Events pods to be ready..."
sleep 10
kubectl wait --for=condition=Ready pod -l eventsource-name=github -n argo-events --timeout=120s || echo "EventSource pod may still be starting..."

log "Argo Events installed successfully"
echo "Webhook endpoint: https://webhooks.local/github"
echo "GitHub webhooks will trigger Tekton pipelines on push events"
