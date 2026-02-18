#!/usr/bin/env bash
set -euo pipefail
# 15-metrics-server.sh - Deploy Metrics Server via Argo CD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 15: Metrics Server – Deploying via Argo CD"

cd "$ROOT_DIR"

# ── 1. Deploy via Argo CD ────────────────────────────────────────────
log "Applying Argo CD project and application for Metrics Server..."

kubectl apply -f "$ROOT_DIR/metrics-server/project.yaml"
kubectl apply -f "$ROOT_DIR/metrics-server/application.yaml"

log "Waiting for Argo CD to sync Metrics Server..."
sleep 10

# Wait for metrics-server deployment to be ready
RETRIES=0
MAX_RETRIES=30
until kubectl get deployment metrics-server -n kube-system &>/dev/null && \
      kubectl wait --for=condition=available --timeout=10s \
        deployment/metrics-server -n kube-system &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    echo "ERROR: Metrics Server not ready after ${MAX_RETRIES} attempts."
    echo "Check ArgoCD application status: kubectl get applications -n argocd metrics-server"
    exit 1
  fi
  echo "  ...waiting for Metrics Server (attempt $RETRIES/$MAX_RETRIES)"
  sleep 10
done

log "Metrics Server is ready"

# ── 2. Verify ────────────────────────────────────────────────────────
log "Verifying Metrics Server..."
kubectl get deployment metrics-server -n kube-system
kubectl get applications -n argocd metrics-server

log "Metrics Server deployed via Argo CD successfully"
log "Usage: kubectl top nodes | kubectl top pods -A"
log "Step 15 complete."

# Setup GitHub webhook proxy for Argo Events
log "Setting up GitHub webhook proxy (smee)..."
pkill -f smee 2>/dev/null || true
sleep 2

log "Starting smee webhook proxy in background..."
smee --url https://smee.io/1iIhi0YC0IolWxXJ --target http://localhost:12000/github &
sleep 2

log "Smee proxy started. GitHub webhooks will be forwarded to Argo Events."
log "Webhook URL: https://smee.io/1iIhi0YC0IolWxXJ"