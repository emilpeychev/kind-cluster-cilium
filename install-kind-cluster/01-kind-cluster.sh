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
log "Kind cluster created successfully"
