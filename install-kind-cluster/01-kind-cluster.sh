#!/usr/bin/env bash
set -euo pipefail
# 01-kind-cluster.sh - Create Kind cluster with Docker network

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

KIND_SUBNET="${KIND_SUBNET:-172.20.0.0/16}"

log "Step 1: Create Kind Cluster"

# Ensure Docker network exists
ensure_kind_network "$KIND_SUBNET"

# Create kind cluster
log "Creating kind cluster"
cd "$ROOT_DIR"
kind create cluster --config=kind-config.yaml

sleep 5

# Fix inotify limits for Kind clusters (prevents "too many open files" errors)
log "Increasing inotify limits on Kind nodes..."
CLUSTER_NAME=$(kind get clusters 2>/dev/null | head -1)
if [ -n "$CLUSTER_NAME" ]; then
  for node in $(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null); do
    docker exec "$node" sysctl -w fs.inotify.max_user_watches=1048576 >/dev/null 2>&1 || true
    docker exec "$node" sysctl -w fs.inotify.max_user_instances=8192 >/dev/null 2>&1 || true
  done
fi

log "Kind cluster created successfully"
