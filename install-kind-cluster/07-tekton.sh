#!/usr/bin/env bash
set -euo pipefail
# 07-tekton.sh - Install Tekton Pipelines and Dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 7: Install Tekton Pipelines"

cd "$ROOT_DIR"

# Add /etc/hosts entry
grep -q "tekton.local" /etc/hosts || echo "$METALLB_IP tekton.local" | sudo tee -a /etc/hosts

# Install Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for controller
kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

# Wait for CRDs
kubectl wait --for=condition=established --timeout=120s crd/pipelines.tekton.dev

log "Waiting for Tekton controller + webhook to be ready"

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-webhook -n tekton-pipelines

log "Waiting for Tekton webhook service endpoints"
until kubectl -n tekton-pipelines get endpoints tekton-pipelines-webhook \
  -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -qE '^[0-9]'; do
  echo "  ...still waiting for endpoints"
  sleep 2
done

log "Enabling Tekton securityContext support (with retry)"
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

# Install Tekton Dashboard
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml
kubectl apply -f Tekton/tekton-dashboard-httproute.yaml

sleep 5

# Create tekton-builds namespace (PSA baseline)
log "Create tekton-builds namespace (PSA baseline)"
kubectl create namespace tekton-builds --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns tekton-builds \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite

sleep 5

# Add Harbor registry secret to tekton-builds
log "Add Harbor registry secret to tekton-builds"
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

sleep 1

# Apply Tekton Pipeline resources
log "Deploying Tekton ServiceAccounts, Pipeline, and Tasks"
kubectl apply -f Tekton-Pipelines/configs/tekton-sa.yaml
kubectl apply -f Tekton-Pipelines/configs/tekton-sa-builds.yaml
kubectl apply -f Tekton-Pipelines/configs/tekton-rbac.yaml
kubectl apply -f Tekton-Pipelines/configs/cosign-keygen-job.yaml
kubectl apply -f Tekton-Pipelines/configs/harbor-ca-configmap.yaml
kubectl apply -f Tekton-Pipelines/tekton-pipeline.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-1-clone-repo.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-2-build-push.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-3-trivy-image-scan.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-4-cosign.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-5-update-tag.yaml

sleep 30

# Setup GitHub Deploy Key for git push
log "GitHub Deploy Key Setup"
DEPLOY_KEY_FILE="$HOME/.ssh/argoCD"
if [ -f "$DEPLOY_KEY_FILE" ]; then
  log "Using existing deploy key: $DEPLOY_KEY_FILE"
else
  echo "ERROR: Deploy key not found at $DEPLOY_KEY_FILE" >&2
  echo ""
  echo "This key is required for Tekton to push image tags back to git."
  echo "The same key is also used by ArgoCD to access the repository."
  echo ""
  echo "To create the key:"
  echo "  ssh-keygen -t ed25519 -C 'argocd-deploy-key' -f $DEPLOY_KEY_FILE -N ''"
  echo ""
  echo "Then add the PUBLIC key to GitHub:"
  echo "  cat ${DEPLOY_KEY_FILE}.pub"
  echo "  → GitHub repo → Settings → Deploy keys → Add deploy key"
  echo "  → Enable 'Allow write access'"
  exit 1
fi

# Create the deploy key secret from existing key
log "Creating GitHub deploy key secret in tekton-builds namespace..."
kubectl create secret generic github-deploy-key \
  --from-file=ssh-privatekey="$DEPLOY_KEY_FILE" \
  --from-literal=known_hosts="$(ssh-keyscan github.com 2>/dev/null)" \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

log "Waiting for Tekton controllers to stabilize"
kubectl wait --for=condition=available deployment/tekton-pipelines-controller -n tekton-pipelines
kubectl wait --for=condition=available deployment/tekton-pipelines-webhook -n tekton-pipelines

log "Tekton Pipelines installed successfully"
echo "Tekton Dashboard: https://tekton.local"
