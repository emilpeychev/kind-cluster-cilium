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


echo "================================================"
echo "* Installing ArgoCD Image Updater"
echo "================================================"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set config.logLevel=info \
  --set config.imageUpdater.autoUpdate.enabled=true \
  --set config.imageUpdater.autoUpdate.method=git \
  --set config.imageUpdater.git.commit.message="chore: update image tags [skip ci]" \
  --set config.imageUpdater.git.push.enabled=true \
  --set config.imageUpdater.git.push.username="argocd-image-updater" \
  --set config.imageUpdater.git.push.email="argocd-image-updater@local"

kubectl rollout restart deployment argocd-image-updater-controller -n argocd
kubectl rollout status deployment argocd-image-updater-controller -n argocd --timeout=60s

echo "================================================"
echo "✔ ArgoCD Image Updater installed"
echo "================================================"