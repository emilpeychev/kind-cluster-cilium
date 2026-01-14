#!/usr/bin/env bash
set -euo pipefail
# Part 2 - Config: Harbor Container Registry Configuration
# This script configures Harbor TLS, CA certificates, and registry secrets

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo
echo "================================================"
echo "* Configuring Harbor: https://harbor.local"
echo "================================================"

# Add entry to /etc/hosts
grep -q "harbor.local" /etc/hosts || echo "172.20.255.201 harbor.local" | sudo tee -a /etc/hosts

# Create Harbor TLS secrets
kubectl create secret tls harbor-tls \
  --cert="${REPO_ROOT}/tls/cert.pem" \
  --key="${REPO_ROOT}/tls/key.pem" \
  -n harbor --dry-run=client -o yaml | kubectl apply -f -

# Create CA certificate ConfigMap for the installer
kubectl create configmap harbor-ca-cert \
  --from-file=ca.crt="${REPO_ROOT}/tls/ca.crt" \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Apply Harbor CA installer
kubectl apply -f "${REPO_ROOT}/Harbor/harbor-ca-installer.yaml"
echo "==> Waiting for CA installer to be ready on all nodes..."
kubectl rollout status daemonset/harbor-ca-installer -n kube-system --timeout=300s || {
    echo "WARNING: CA installer timed out. Checking pod status..."
    kubectl get pods -n kube-system -l name=harbor-ca-installer
    kubectl describe pods -n kube-system -l name=harbor-ca-installer
    echo "Continuing with setup despite CA installer timeout..."
}

kubectl apply -f "${REPO_ROOT}/Harbor/harbor-httproute.yaml"

# Restart containerd on all nodes to pick up new CA certificates
echo "==> Restarting containerd on all nodes to trust Harbor CA"
docker exec test-cluster-1-control-plane systemctl restart containerd || echo "WARNING: Failed to restart containerd on control-plane"
docker exec test-cluster-1-worker systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker"
docker exec test-cluster-1-worker2 systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker2"
echo "==> Containerd restarted on all nodes"

# Add harbor.local to /etc/hosts on all Kind nodes so containerd can resolve it
echo "==> Adding harbor.local to Kind nodes /etc/hosts"
GATEWAY_LB_IP=$(kubectl get svc istio-gateway-istio -n istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for node in test-cluster-1-control-plane test-cluster-1-worker test-cluster-1-worker2; do
  docker exec "$node" bash -c "grep -q 'harbor.local' /etc/hosts || echo '${GATEWAY_LB_IP} harbor.local' >> /etc/hosts"
done
echo "==> harbor.local added to Kind nodes"

sleep 15
# Create demo-apps namespace and Harbor registry secret
echo "==> Setting up demo-apps namespace and Harbor credentials"
kubectl create namespace demo-apps --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n demo-apps \
  --dry-run=client -o yaml | kubectl apply -f -

echo "================================================"
echo "✔ Part 2 Config complete - Harbor configured"
echo "================================================"
echo "Next: Run setup-scripts/03-tekton-install.sh"
