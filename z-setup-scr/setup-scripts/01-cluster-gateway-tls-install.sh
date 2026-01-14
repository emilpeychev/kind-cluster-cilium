#!/usr/bin/env bash
set -euo pipefail
# Part 1 - Install: Cluster, Gateways, and TLS infrastructure
# This script installs the core cluster components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

KIND_SUBNET="172.20.0.0/16"

echo "==> Ensuring Docker 'kind' network exists"

if docker network inspect kind >/dev/null 2>&1; then
  echo "==> Docker 'kind' network already exists"
else
  docker network create kind --subnet "${KIND_SUBNET}"
fi

docker network inspect kind | grep Subnet || true

# Create kind cluster
echo "==> Creating kind cluster"
kind create cluster --config="${REPO_ROOT}/kind-config.yaml"

sleep 5
# Install MetalLB
echo "==> Installing MetalLB (native)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

sleep 5
# Install Cilium CNI
echo "==> Installing Cilium"
cilium install \
  --version 1.18.4 \
  --set kubeProxyReplacement=true \
  --set kubeProxyReplacementMode=strict \
  --set cni.exclusive=false \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.244.0.0/16 \
  --set k8s.requireIPv4PodCIDR=true

cilium status --wait

sleep 30
# Configure MetalLB L2 pool
echo "==> Configuring MetalLB L2 pool"
kubectl apply -f "${REPO_ROOT}/metalLB/metallb-config.yaml"

sleep 5
# Install Gateway API CRDs
echo "==> Installing Gateway API CRDs"
kubectl apply --server-side -f \
https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
sleep 5

# Create istio-gateway namespace
echo "==> Creating istio-gateway namespace (ambient)"
kubectl create namespace istio-gateway --dry-run=client -o yaml | kubectl apply -f -
# Label namespace for ambient mode data plane operation
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient --overwrite
sleep 2

# HARD wait for dataplane convergence
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=cilium --timeout=5m
kubectl wait --for=condition=Ready node --all --timeout=5m

# Install Istio Ambient
echo "==> Installing Istio Ambient"
istioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway' \
  --skip-confirmation

# HARD waits
kubectl wait -n istio-system --for=condition=available deployment/istiod --timeout=5m
kubectl wait -n istio-system --for=condition=Ready pod -l app=ztunnel --timeout=5m
kubectl wait -n istio-gateway --for=condition=available deployment/istio-ingressgateway --timeout=5m

kubectl wait svc istio-ingressgateway \
  -n istio-gateway \
  --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  --timeout=120s

echo "================================================"
echo "✔ Part 1 Install complete - Core infrastructure installed"
echo "================================================"
echo "Next: Run config-scripts/01-cluster-gateway-tls-config.sh"
