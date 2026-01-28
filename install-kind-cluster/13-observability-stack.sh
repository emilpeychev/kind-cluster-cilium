#!/bin/bash
set -euo pipefail
# 13-prometheus - Prometheus + Grafana for Argo CD (GitOps-safe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 13: Observability (Prometheus + Grafana) – Artifact & GitOps setup"

cd "$ROOT_DIR"

# 1. Package Prometheus Helm chart
log "Packaging and pushing Prometheus Helm chart to Harbor..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update >/dev/null

helm pull prometheus-community/prometheus --version 28.6.0

# 2. Ensure Harbor project exists
log "Ensuring Harbor project 'helm' exists..."

curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"helm","public":false}' || true

# Login to Harbor for helm push
echo "Harbor12345" | helm registry login harbor.local -u admin --password-stdin

# 3. Push Helm chart to Harbor OCI repo
helm push prometheus-28.6.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f prometheus-28.6.0.tgz

# 3b. Package & push Grafana Helm chart
log "Packaging and pushing Grafana Helm chart to Harbor..."
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm pull grafana/grafana --version 10.5.12 || true
helm push grafana-10.5.12.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f grafana-10.5.12.tgz

# 4. Create / load Harbor robot account (system-level, no project_id needed)
log "Ensuring Harbor robot account for Argo CD..."

ROBOT_ENV="$ROOT_DIR/.harbor-robot-pass.env"

# Try to load existing robot credentials; if missing or invalid, create a new robot.
if [[ -f "$ROBOT_ENV" ]]; then
  source "$ROBOT_ENV"
  # Use literal username 'robot$argocd' (dollar sign must not be expanded as a variable)
  HTTP_CODE=$(curl -sk -u 'robot$argocd:'"$ROBOT_PASS" -o /dev/null -w "%{http_code}" https://harbor.local/api/v2.0/projects/helm || true)
  if [[ "$HTTP_CODE" == "401" || -z "${ROBOT_PASS:-}" ]]; then
    log "Existing robot credentials invalid or missing; creating new robot"
    NEW_ROBOT_PASS=$(
      curl -sk -u admin:Harbor12345 \
        -X POST https://harbor.local/api/v2.0/robots \
        -H "Content-Type: application/json" \
        -d '{
          "name": "argocd",
          "level": "system",
          "duration": -1,
          "permissions": [
            {
              "kind": "project",
              "namespace": "helm",
              "access": [
                { "resource": "repository", "action": "pull" },
                { "resource": "repository", "action": "push" },
                { "resource": "repository", "action": "read" },
                { "resource": "artifact", "action": "read" }
              ]
            }
          ]
        }' | jq -r '.secret // empty'
    )
    if [[ -n "$NEW_ROBOT_PASS" ]]; then
      echo "export ROBOT_PASS='$NEW_ROBOT_PASS'" > "$ROBOT_ENV"
      chmod 600 "$ROBOT_ENV"
      source "$ROBOT_ENV"
    else
      log "Failed to create robot or extract secret"
    fi
  else
    log "Loaded existing robot credentials"
  fi
else
  log "No robot credentials found; creating robot"
  NEW_ROBOT_PASS=$(
    curl -sk -u admin:Harbor12345 \
      -X POST https://harbor.local/api/v2.0/robots \
      -H "Content-Type: application/json" \
      -d '{
        "name": "argocd",
        "level": "system",
        "duration": -1,
        "permissions": [
          {
            "kind": "project",
            "namespace": "helm",
            "access": [
              { "resource": "repository", "action": "pull" },
              { "resource": "repository", "action": "push" },
              { "resource": "repository", "action": "read" },
              { "resource": "artifact", "action": "read" }
            ]
          }
        ]
      }' | jq -r '.secret // empty'
  )
  if [[ -n "$NEW_ROBOT_PASS" ]]; then
    echo "export ROBOT_PASS='$NEW_ROBOT_PASS'" > "$ROBOT_ENV"
    chmod 600 "$ROBOT_ENV"
    source "$ROBOT_ENV"
  fi
fi

if [[ -z "${ROBOT_PASS:-}" ]]; then
  echo "ERROR: ROBOT_PASS is empty. Cannot register Argo CD repo."
  exit 1
fi

# 5. Register Harbor repo in Argo CD (OCI)
log "Registering Harbor Helm OCI repo in Argo CD..."

argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS" \
  --upsert \
  || true

# Also create/update the repository Secret in argocd namespace so ArgoCD (repo-server)
# can pick it up even if `argocd` CLI is not available.
if command -v kubectl >/dev/null 2>&1; then
  source "$ROOT_DIR/.harbor-robot-pass.env" || true
  kubectl create secret generic harbor-helm-repo -n argocd \
    --from-literal=url=https://harbor.local \
    --from-literal=username='robot$argocd' \
    --from-literal=password="$ROBOT_PASS" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label secret harbor-helm-repo -n argocd argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
fi

# 6. Local DNS convenience
grep -q "grafana.local" /etc/hosts || \
  echo "$METALLB_IP grafana.local" | sudo tee -a /etc/hosts >/dev/null
grep -q "kiali.local" /etc/hosts || \
  echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts >/dev/null
grep -q "prometheus.local" /etc/hosts || \
  echo "$METALLB_IP prometheus.local" | sudo tee -a /etc/hosts >/dev/null

# 7. Apply all observability Argo CD manifests (projects, applications, httproutes)
log "Applying Argo CD observability applications..."

# Create namespaces if they don't exist
kubectl create namespace kiali 2>/dev/null || true
kubectl create namespace monitoring 2>/dev/null || true

# Apply kiali manifests (project, application, httproute)
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/project.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/httproute.yaml"

# Apply prometheus/grafana manifests (project, applications, httproutes)
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/project.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/grafana-application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/grafana-httproute.yaml"

log "Waiting for Argo CD applications to sync..."
sleep 5

# Show application status
kubectl get applications -n argocd -l app.kubernetes.io/part-of=observability 2>/dev/null || \
  kubectl get applications -n argocd

log "Observability stack deployed via Argo CD"
log "URLs (once synced):"
log "  Kiali:      https://kiali.local"
log "  Prometheus: https://prometheus.local"
log "  Grafana:    https://grafana.local"
log "Step 13 complete."
