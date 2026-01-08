#!/usr/bin/env bash
set -euo pipefail

echo "==> Running Tekton Pipeline Demo"

# Delete any existing PipelineRun
echo "==> Cleaning up previous pipeline runs"
kubectl delete pipelinerun clone-build-push-run -n tekton-builds --ignore-not-found=true

# Wait a moment for cleanup
sleep 5

# Apply fresh PipelineRun
echo "==> Starting new pipeline run"
kubectl apply -f Tekton-Pipelines/tekton-pipeline-run.yaml

echo "==> Waiting for PipelineRun to initialize"
sleep 10

# Show status
echo "==> Pipeline status:"
kubectl get pipelinerun clone-build-push-run -n tekton-builds

echo "==> Pipeline pods:"
kubectl get pods -n tekton-builds -l tekton.dev/pipelineRun=clone-build-push-run

echo "================================================"
echo "* Monitor pipeline progress:"
echo "================================================"
echo "kubectl logs -f -n tekton-builds -l tekton.dev/pipelineRun=clone-build-push-run"
echo "kubectl get pipelinerun -n tekton-builds -w"
echo "kubectl get pods -n tekton-builds -w"
echo "================================================"