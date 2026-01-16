#!/usr/bin/env bash
set -euo pipefail
# 10-argo-workflows.sh - Install Argo Workflows

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 10: Install Argo Workflows"

cd "$ROOT_DIR"

# Add /etc/hosts entry
grep -q "workflows.local" /etc/hosts || echo "$METALLB_IP workflows.local" | sudo tee -a /etc/hosts

# Install Argo Workflows
kubectl create namespace argo 2>/dev/null || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.2/quick-start-minimal.yaml

# Wait for Argo Workflows to be ready
log "Waiting for Argo Workflows controller..."
kubectl wait --for=condition=available --timeout=300s deployment/workflow-controller -n argo
kubectl wait --for=condition=available --timeout=300s deployment/argo-server -n argo

# Disable TLS on argo-server (gateway handles TLS termination)
log "Configuring argo-server for HTTP mode..."
kubectl patch deployment argo-server -n argo --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--secure=false"}]'

# Update readiness probe to use HTTP instead of HTTPS
kubectl patch deployment argo-server -n argo --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/scheme","value":"HTTP"}]'

log "Waiting for Argo Server to restart..."
kubectl rollout status deployment/argo-server -n argo --timeout=120s

# Apply HTTPRoute for Argo Workflows UI
kubectl apply -f Argo-Workflows/workflows-httproute.yaml

log "Argo Workflows installed successfully"
echo "Argo Workflows UI: https://workflows.local"
