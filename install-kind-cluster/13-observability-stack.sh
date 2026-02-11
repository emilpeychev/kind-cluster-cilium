#!/bin/bash
set -euo pipefail
# 13-observability-stack - Deploy observability stack via Argo CD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 13: Observability Stack – Deploying via Argo CD"

cd "$ROOT_DIR"

# 1. Verify Harbor robot credentials exist (dependency on step 12)
ROBOT_ENV="$ROOT_DIR/.harbor-robot-pass.env"

if [[ ! -f "$ROBOT_ENV" ]]; then
  echo "ERROR: Harbor robot credentials not found at $ROBOT_ENV"
  echo "Please run step 12 (12-harbor-observability-charts.sh) first"
  exit 1
fi

source "$ROBOT_ENV"

if [[ -z "${ROBOT_PASS:-}" ]]; then
  echo "ERROR: ROBOT_PASS is empty in $ROBOT_ENV"
  echo "Please run step 12 (12-harbor-observability-charts.sh) first"
  exit 1
fi

log "Harbor credentials validated"

# 2. Apply all observability Argo CD manifests (projects, applications, httproutes)
log "Applying Argo CD observability applications..."

# Create namespaces if they don't exist
kubectl create namespace istio-system 2>/dev/null || true
kubectl create namespace monitoring 2>/dev/null || true

# Apply prometheus/grafana manifests first (project, applications, httproutes)
log "Deploying Prometheus and Grafana..."
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/project.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/prometheus-httproute.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/grafana-application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/prometheus/grafana-httproute.yaml"

# Apply kiali manifests (project, application, httproute) - depends on Prometheus
log "Deploying Kiali (depends on Prometheus)..."
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/project.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/httproute.yaml"

log "Waiting for Argo CD applications to sync..."
sleep 5

# Show application status
kubectl get applications -n argocd -l app.kubernetes.io/part-of=observability 2>/dev/null || \
  kubectl get applications -n argocd

log "Observability stack deployed via Argo CD"
log "URLs (once synced):"
log "  Prometheus: https://prometheus.local"
log "  Grafana:    https://grafana.local"
log "  Kiali:      https://kiali.local"
log "Step 13 complete."
