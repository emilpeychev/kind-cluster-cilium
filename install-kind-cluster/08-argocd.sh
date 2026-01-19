#!/usr/bin/env bash
set -euo pipefail
# 08-argocd.sh - Install ArgoCD and deploy applications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 8: Install ArgoCD"

require_cmd argocd

cd "$ROOT_DIR"

# Add /etc/hosts entries
grep -q "argocd.local" /etc/hosts || echo "$METALLB_IP argocd.local" | sudo tee -a /etc/hosts
grep -q "demo-app1.local" /etc/hosts || echo "$METALLB_IP demo-app1.local" | sudo tee -a /etc/hosts

# Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Apply custom configurations via Kustomize
kubectl apply -k ArgoCD/
sleep 1
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd

# Wait for Gateway to be ready and routing traffic
log "Waiting for Istio Gateway to be ready..."
kubectl wait --for=condition=Programmed --timeout=120s gateway/istio-gateway -n istio-gateway || true

# Wait for Gateway pods to be fully ready
kubectl wait --for=condition=ready --timeout=60s pod -l gateway.networking.k8s.io/gateway-name=istio-gateway -n istio-gateway || true

# Verify connectivity to ArgoCD through the Gateway
log "Verifying Gateway connectivity to ArgoCD..."
RETRIES=30
for i in $(seq 1 $RETRIES); do
  if curl -sk --connect-timeout 5 "https://$METALLB_IP" -H "Host: argocd.local" >/dev/null 2>&1; then
    log "Gateway is routing traffic to ArgoCD"
    break
  fi
  if [ "$i" -eq "$RETRIES" ]; then
    log "WARNING: Gateway connectivity check timed out, proceeding anyway..."
  fi
  echo "Waiting for Gateway connectivity... ($i/$RETRIES)"
  sleep 2
done

# Login and add repository
log "Logging into ArgoCD and adding repository"
NS=argocd
SERVER=argocd.local
SSH_KEY="$HOME/.ssh/argoCD"
REPO="git@github.com:emilpeychev/kind-cluster-cilium.git"

PASSWORD="$(kubectl -n "$NS" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

argocd login "$SERVER" \
  --username admin \
  --password "$PASSWORD" \
  --grpc-web \
  --insecure

# Add Git SSH host to known_hosts
HOST=github.com
ssh-keygen -F "$HOST" >/dev/null 2>&1 || ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts

# Add Git repository
argocd repo add "$REPO" \
  --ssh-private-key-path "$SSH_KEY" \
  --grpc-web

# Push initial image to Harbor so ArgoCD has something to deploy
log "Pushing initial image to Harbor..."
docker pull nginxdemos/hello:latest
docker tag nginxdemos/hello:latest harbor.local/library/demo-app:latest

# Configure Docker to trust Harbor CA and push image
sudo mkdir -p /etc/docker/certs.d/harbor.local
sudo cp "$ROOT_DIR/tls/ca.crt" /etc/docker/certs.d/harbor.local/ca.crt
echo "Harbor12345" | docker login harbor.local -u admin --password-stdin
docker push harbor.local/library/demo-app:latest
log "Initial image pushed to Harbor successfully!"

# Deploy ArgoCD Project and ApplicationSet
kubectl apply -f ArgoCD-demo-apps/projects/application-sets-projects.yaml
kubectl apply -f ArgoCD-demo-apps/applicationsets/application-sets.yaml
kubectl apply -k ArgoCD-demo-apps/apps/

log "Waiting for ArgoCD Applications to be created..."
sleep 10

# Show ArgoCD Applications status
kubectl get applications -n argocd

log "ArgoCD installed successfully"
echo "ArgoCD URL: https://argocd.local"
echo "Admin password: $PASSWORD"
