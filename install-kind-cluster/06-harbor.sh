#!/usr/bin/env bash
set -euo pipefail
# 06-harbor.sh - Install Harbor container registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 6: Install Harbor Registry"

require_cmd helm

cd "$ROOT_DIR"

# Add /etc/hosts entry
grep -q "harbor.local" /etc/hosts || echo "$METALLB_IP harbor.local" | sudo tee -a /etc/hosts

# Install Harbor via Helm
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor --version 1.18.1 --create-namespace \
  -n harbor \
  -f Harbor/harbor-values.yaml

# Create Harbor TLS secrets
kubectl create secret tls harbor-tls \
  --cert=tls/cert.pem \
  --key=tls/key.pem \
  -n harbor --dry-run=client -o yaml | kubectl apply -f -

# Create CA certificate ConfigMap for the installer
kubectl create configmap harbor-ca-cert \
  --from-file=ca.crt=tls/ca.crt \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Apply Harbor CA installer
kubectl apply -f Harbor/harbor-ca-installer.yaml
log "Waiting for CA installer to be ready on all nodes..."
kubectl rollout status daemonset/harbor-ca-installer -n kube-system --timeout=300s || {
    echo "WARNING: CA installer timed out. Continuing..."
}

kubectl apply -f Harbor/harbor-httproute.yaml

# Restart containerd on all nodes to pick up new CA certificates
log "Restarting containerd on all nodes to trust Harbor CA"
docker exec test-cluster-1-control-plane systemctl restart containerd || echo "WARNING: Failed to restart containerd on control-plane"
docker exec test-cluster-1-worker systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker"
docker exec test-cluster-1-worker2 systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker2"

# Add harbor.local to /etc/hosts on all Kind nodes
log "Adding harbor.local to Kind nodes /etc/hosts"
GATEWAY_LB_IP=$(kubectl get svc istio-gateway-istio -n istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for node in test-cluster-1-control-plane test-cluster-1-worker test-cluster-1-worker2; do
  docker exec "$node" bash -c "grep -q 'harbor.local' /etc/hosts || echo '${GATEWAY_LB_IP} harbor.local' >> /etc/hosts"
done

sleep 15

# Create demo-apps namespace and Harbor registry secret
log "Setting up demo-apps namespace and Harbor credentials"
kubectl create namespace demo-apps --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n demo-apps \
  --dry-run=client -o yaml | kubectl apply -f -

log "Harbor installed successfully"
echo "Harbor URL: https://harbor.local"
echo "Credentials: admin / Harbor12345"
