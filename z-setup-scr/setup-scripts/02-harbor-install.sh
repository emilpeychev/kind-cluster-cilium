#!/usr/bin/env bash
set -euo pipefail
# Part 2 - Install: Harbor Container Registry
# This script installs Harbor via Helm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo
echo "================================================"
echo "* Installing Harbor: https://harbor.local"
echo "================================================"

helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor --version 1.18.1 --create-namespace \
  -n harbor \
  -f "${REPO_ROOT}/Harbor/harbor-values.yaml"

echo "================================================"
echo "✔ Part 2 Install complete - Harbor installed"
echo "================================================"
echo "Next: Run config-scripts/02-harbor-config.sh"
