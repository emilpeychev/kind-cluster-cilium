#!/usr/bin/env bash
set -euo pipefail
# 11-deploy-apps.sh - Build initial demo-app image and deploy applications via manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 11: Deploy Applications"

cd "$ROOT_DIR"

# Add /etc/hosts entries for new apps
grep -q "httpbin.local" /etc/hosts || echo "$METALLB_IP httpbin.local" | sudo tee -a /etc/hosts
grep -q "demo-app1.local" /etc/hosts || echo "$METALLB_IP demo-app1.local" | sudo tee -a /etc/hosts

# Create namespaces
log "Creating namespaces..."
kubectl create namespace httpbin 2>/dev/null || true
kubectl create namespace demo-apps 2>/dev/null || true

# Build and push initial demo-app image to Harbor
log "Building and pushing initial demo-app image to Harbor..."

# Generate timestamp tag (same format as Tekton pipeline)
IMAGE_TAG=$(date -u +"%Y%m%d-%H%M%S")
IMAGE_URL="harbor.local/library/demo-app:${IMAGE_TAG}"

# Build with docker and push to Harbor
cd "$ROOT_DIR/demo-app"
docker build -t "$IMAGE_URL" .
docker push "$IMAGE_URL"

log "Pushed image: $IMAGE_URL"

# Update manifests with the built image tag
cd "$ROOT_DIR"
sed -i "s|harbor.local/library/demo-app:.*|harbor.local/library/demo-app:${IMAGE_TAG}|" ArgoCD-demo-apps/apps/deployment.yaml
sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|" ArgoCD-demo-apps/apps/kustomization.yaml

# Create Harbor pull secret in demo-apps namespace
log "Creating Harbor pull secret in demo-apps namespace..."
kubectl create secret docker-registry harbor-regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n demo-apps \
  --dry-run=client -o yaml | kubectl apply -f -

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

# Wait for demo-app deployment
log "Waiting for demo-app to be ready..."
sleep 10
kubectl wait --for=condition=available --timeout=120s deployment/demo-app1 -n demo-apps || true

# Verify deployments
log "Verifying deployments..."
kubectl get deployments -n demo-apps
kubectl get deployments -n httpbin

log "Applications deployed successfully"
echo "Demo App:    https://demo-app1.local"
echo "HTTPBin API: https://httpbin.local"
echo ""
echo "Test HTTPBin: curl -k https://httpbin.local/get"
