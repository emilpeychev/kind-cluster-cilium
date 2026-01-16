#!/usr/bin/env bash
set -euo pipefail
# 02-metallb.sh - Install MetalLB load balancer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 2: Install MetalLB"

# Install MetalLB from local manifest
log "Installing MetalLB (native)"
kubectl apply -f "$ROOT_DIR/metalLB/metallb-native.yaml"

sleep 5

# Wait for MetalLB controller
log "Waiting for MetalLB controller..."
kubectl wait --for=condition=available --timeout=10s \
  deployment/controller -n metallb-system || true

log "MetalLB installed successfully"
