#!/usr/bin/env bash
set -euo pipefail
# Part 4 - Install: ArgoCD
# This script installs ArgoCD and Image Updater

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

# Install via Helm with values file (includes Harbor CA and registry config)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd-image-updater argo/argocd-image-updater --version 1.0.4 \
  --namespace argocd \
  -f "${REPO_ROOT}/ArgoCD-Image-Updater/values.yaml"

echo "==> Waiting for ArgoCD Image Updater to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/argocd-image-updater-controller -n argocd || {
    echo "WARNING: Image Updater deployment not ready. Check with:"
    echo "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater"
}

echo "==> Creating SSH git credentials for Image Updater..."
repo_secret=$(kubectl get secret -n argocd | awk '/^repo-[0-9]+/ {print $1; exit}')
if [[ -n "${repo_secret}" ]]; then
  tmpkey=$(mktemp)
  trap 'rm -f "$tmpkey"' EXIT
  kubectl get secret -n argocd "$repo_secret" -o jsonpath='{.data.sshPrivateKey}' | base64 -d > "$tmpkey"
  kubectl create secret generic ssh-git-creds -n argocd \
    --from-file=sshPrivateKey="$tmpkey" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "WARNING: No ArgoCD repo secret found, skipping ssh-git-creds creation"
fi

echo "==> Setting git commit identity for Image Updater..."
kubectl patch configmap -n argocd argocd-image-updater-config --type merge \
  -p '{"data":{"git.user":"argocd-image-updater","git.email":"argocd-image-updater@local"}}'

echo "==> Adding GitHub known_hosts..."
kubectl patch configmap -n argocd argocd-image-updater-ssh-config --type merge \
  -p '{"data":{"known_hosts":"github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"}}'

echo "==> Applying ImageUpdater CR..."
kubectl apply -f "${REPO_ROOT}/ArgoCD-Image-Updater/imageupdater-cr.yaml"

echo "==> Restarting Image Updater controller to pick up all configs..."
kubectl rollout restart -n argocd deployment/argocd-image-updater-controller
kubectl rollout status -n argocd deployment/argocd-image-updater-controller --timeout=120s

echo "================================================"
echo "✔ Part 4 Install complete - ArgoCD + Image Updater installed"
echo "================================================"
echo "Next: Run config-scripts/04-argocd-config.sh"
