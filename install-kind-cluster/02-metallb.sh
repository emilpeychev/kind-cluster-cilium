#!/usr/bin/env bash
set -euo pipefail
# 02-metallb.sh - Install MetalLB load balancer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 2: Install MetalLB"

# Install MetalLB from upstream (v0.14.5)
log "Installing MetalLB (native)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

sleep 5

log "MetalLB installed successfully"
