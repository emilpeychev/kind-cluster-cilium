#!/usr/bin/env bash
set -euo pipefail
# 11-deploy-apps.sh - Deploy additional applications via manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 11: Deploy Applications"

cd "$ROOT_DIR"

# Add /etc/hosts entries for new apps
grep -q "httpbin.local" /etc/hosts || echo "$METALLB_IP httpbin.local" | sudo tee -a /etc/hosts

# Create namespaces
log "Creating namespaces..."
kubectl create namespace httpbin 2>/dev/null || true

# Apply kustomize manifests for httpbin API
log "Deploying httpbin API..."
kubectl apply -k ArgoCD-demo-apps/api/

# Wait for httpbin deployment
log "Waiting for httpbin to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/httpbin -n httpbin

# Apply ArgoCD Projects
log "Applying ArgoCD Projects..."
kubectl apply -f ArgoCD-demo-apps/projects/

# Sync ArgoCD ApplicationSets to pick up new apps
log "Applying ArgoCD ApplicationSets..."
kubectl apply -f ArgoCD-demo-apps/applicationsets/

# Verify deployments
log "Verifying deployments..."
kubectl get deployments -n demo-apps
kubectl get deployments -n httpbin

log "Applications deployed successfully"
echo "Demo App:    https://demo-app1.local"
echo "HTTPBin API: https://httpbin.local"
echo ""
echo "Test HTTPBin: curl -k https://httpbin.local/get"
