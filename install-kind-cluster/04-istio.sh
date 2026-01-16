#!/usr/bin/env bash
set -euo pipefail
# 04-istio.sh - Install Gateway API CRDs and Istio Ambient

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 4: Install Gateway API and Istio Ambient"

require_cmd istioctl

# Install Gateway API CRDs
log "Installing Gateway API CRDs"
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
sleep 5

# Create istio-gateway namespace
log "Creating istio-gateway namespace (ambient)"
kubectl create namespace istio-gateway --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient --overwrite
sleep 2

# Wait for cluster readiness
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=cilium --timeout=5m
kubectl wait --for=condition=Ready node --all --timeout=5m

# Install Istio Ambient
log "Installing Istio Ambient"
istioctl install \
  --set profile=ambient \
  --skip-confirmation

kubectl wait -n istio-system \
  --for=condition=Ready pod \
  -l app=istiod \
  --timeout=5m

kubectl apply -f "$ROOT_DIR/gateway.yaml"

log "Istio Ambient installed successfully"
