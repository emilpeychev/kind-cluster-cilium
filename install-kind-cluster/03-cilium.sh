#!/usr/bin/env bash
set -euo pipefail
# 03-cilium.sh - Install Cilium CNI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 3: Install Cilium CNI"

require_cmd cilium

log "Installing Cilium"
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

# Configure MetalLB L2 pool (requires Cilium to be ready)
log "Configuring MetalLB L2 pool"
kubectl apply -f "$ROOT_DIR/metalLB/metallb-config.yaml"

sleep 5
log "Cilium CNI installed successfully"
