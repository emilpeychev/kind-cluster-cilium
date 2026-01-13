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
echo "✔ ArgoCD installed"
echo "================================================"

echo "================================================"
echo "* Installing ArgoCD Image Updater (Helm)"
echo "================================================"

# Apply Harbor registry secret
kubectl apply -f "${REPO_ROOT}/ArgoCD-Image-Updater/harbor-registry-secret.yaml"

# Install via Helm with values file
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  -f "${REPO_ROOT}/ArgoCD-Image-Updater/values.yaml"

echo "==> Waiting for ArgoCD Image Updater to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/argocd-image-updater -n argocd || {
    echo "WARNING: Image Updater deployment not ready. Check with:"
    echo "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater"
}

echo "================================================"
echo "✔ Part 4 Install complete - ArgoCD + Image Updater installed"
echo "================================================"
echo "Next: Run config-scripts/04-argocd-config.sh"
