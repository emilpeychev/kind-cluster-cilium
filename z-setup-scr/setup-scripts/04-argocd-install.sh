#!/usr/bin/env bash
set -euo pipefail
# Part 4 - Install: ArgoCD
# This script installs ArgoCD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "================================================"
echo "* Installing ArgoCD: https://argocd.local"
echo "================================================"

# 1. Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "================================================"
echo "✔ Part 4 Install complete - ArgoCD installed"
echo "================================================"
echo "Next: Run config-scripts/04-argocd-config.sh"
