#!/usr/bin/env bash
set -euo pipefail
# Part 3 - Install: Tekton Pipelines and Dashboard
# This script installs Tekton Pipelines and Dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "================================================"
echo "* Installing Tekton Pipelines: https://tekton.local"
echo "================================================"

# Install Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for controller
kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

# Wait for CRDs
kubectl wait --for=condition=established --timeout=120s crd/pipelines.tekton.dev

echo "==> Waiting for Tekton controller + webhook to be ready"

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-webhook -n tekton-pipelines

echo "==> Waiting for Tekton webhook service endpoints"
until kubectl -n tekton-pipelines get endpoints tekton-pipelines-webhook \
  -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -qE '^[0-9]'; do
  echo "  ...still waiting for endpoints"
  sleep 2
done

# Install Tekton Dashboard
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml

sleep 5

echo "================================================"
echo "✔ Part 3 Install complete - Tekton installed"
echo "================================================"
echo "Next: Run config-scripts/03-tekton-config.sh"
