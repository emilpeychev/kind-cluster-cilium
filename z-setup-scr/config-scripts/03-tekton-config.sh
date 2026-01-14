#!/usr/bin/env bash
set -euo pipefail
# Part 3 - Config: Tekton Pipelines Configuration and Automation
# This script configures Tekton and runs the initial pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "================================================"
echo "* Configuring Tekton Pipelines: https://tekton.local"
echo "================================================"

# /etc/hosts
grep -q "tekton.local" /etc/hosts || echo "172.20.255.201 tekton.local" | sudo tee -a /etc/hosts

echo "==> Enabling Tekton securityContext support (with retry)"
for i in {1..30}; do
  if kubectl patch configmap feature-flags -n tekton-pipelines \
    --type merge \
    -p '{"data":{"set-security-context":"true"}}'; then
    echo "✅ Patched feature-flags"
    break
  fi
  echo "  patch failed (webhook not reachable yet). retry $i/30..."
  sleep 2
done

kubectl apply -f "${REPO_ROOT}/Tekton/tekton-dashboard-httproute.yaml"

echo "================================================"
echo " Create tekton-builds namespace (PSA baseline)"
echo "================================================"

kubectl create namespace tekton-builds --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns tekton-builds \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite
sleep 5

echo "================================================"
echo " Add Harbor registry secret to tekton-builds"
echo "================================================"

kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

sleep 1
# Apply Tekton Pipeline resources
echo "==> Deploying Tekton ServiceAccounts, Pipeline, and Tasks"
kubectl apply -f "${REPO_ROOT}/Tekton-Pipelines/configs/"
kubectl apply -f "${REPO_ROOT}/Tekton-Pipelines/tekton-pipeline.yaml"
kubectl apply -f "${REPO_ROOT}/Tekton-Pipelines/tekton-task-1-clone-repo.yaml"
kubectl apply -f "${REPO_ROOT}/Tekton-Pipelines/tekton-task-2-build-push.yaml"
sleep 30

echo "==> Waiting for Tekton controllers to stabilize"
kubectl wait --for=condition=available deployment/tekton-pipelines-controller -n tekton-pipelines
kubectl wait --for=condition=available deployment/tekton-pipelines-webhook -n tekton-pipelines
sleep 20

echo "==> Running initial Tekton pipeline to build demo app image"
kubectl create -f "${REPO_ROOT}/Tekton-Pipelines/tekton-pipeline-run.yaml"

echo "==> Waiting for pipeline to complete..."
kubectl wait --for=condition=Succeeded --timeout=300s pipelinerun/clone-build-push-run -n tekton-builds || {
    echo "WARNING: Pipeline did not complete successfully. Check with:"
    echo "kubectl get pipelineruns -n tekton-builds"
    echo "kubectl logs -f pipelinerun/clone-build-push-run -n tekton-builds"
}
sleep 1

echo "================================================"
echo "✔ Part 3 Config complete - Tekton configured"
echo "================================================"
echo "Next: Run setup-scripts/04-argocd-install.sh"
