#!/usr/bin/env bash
set -euo pipefail
# 08-tekton.sh - Install Tekton Pipelines and Dashboard
#
# SECURITY ARCHITECTURE:
# =====================
# tekton-pipelines namespace: Tekton control plane (controllers, webhooks)
#   - Runs with privileged service accounts
#   - Manages pipeline execution
#   - Pod Security: Privileged (required for controllers)
#
# tekton-builds namespace: Pipeline execution environment
#   - Where PipelineRuns actually execute
#   - Restricted security context (PSA baseline)
#   - Contains build-specific secrets (Harbor, GitHub)
#   - Isolated from control plane

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 8: Install Tekton Pipelines (GitOps via ArgoCD)"

cd "$ROOT_DIR"

# Add /etc/hosts entry
grep -q "tekton.local" /etc/hosts || echo "$METALLB_IP tekton.local" | sudo tee -a /etc/hosts

# 1. Package tekton pipelines and push to harbor
log "Packaging Tekton Pipelines Helm chart..."

# Tekton now deployed via Git (official manifests) instead of Helm
# Version v0.70.0 compatible with K8s 1.33+

# Harbor setup no longer needed - using Git deployment
# 3. Create / load Harbor robot account (system-level)
log "Ensuring Harbor robot account for Argo CD..."

ROBOT_ENV="$ROOT_DIR/.harbor-robot-pass.env"

# Try to load and validate existing credentials
if [[ -f "$ROBOT_ENV" ]]; then
  source "$ROBOT_ENV"
  HTTP_CODE=$(curl -sk -u 'robot$argocd:'"$ROBOT_PASS" -o /dev/null -w "%{http_code}" https://harbor.local/api/v2.0/projects/helm 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    log "Loaded existing robot credentials (valid)"
  else
    log "Existing credentials invalid, recreating robot..."
    # Delete existing robot
    EXISTING_ROBOT_ID=$(curl -sk -u admin:Harbor12345 \
      "https://harbor.local/api/v2.0/robots?q=name%3Dargocd" | jq -r '.[0].id // empty')
    [[ -n "$EXISTING_ROBOT_ID" ]] && curl -sk -u admin:Harbor12345 -X DELETE "https://harbor.local/api/v2.0/robots/$EXISTING_ROBOT_ID"
    unset ROBOT_PASS
  fi
fi

# Create robot if needed
if [[ -z "${ROBOT_PASS:-}" ]]; then
  ROBOT_PASS=$(
    curl -sk -u admin:Harbor12345 \
      -X POST "https://harbor.local/api/v2.0/robots" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "argocd",
        "level": "system",
        "duration": -1,
        "permissions": [
          {
            "kind": "project",
            "namespace": "helm",
            "access": [
              { "resource": "repository", "action": "pull" },
              { "resource": "repository", "action": "push" },
              { "resource": "repository", "action": "read" },
              { "resource": "artifact", "action": "read" }
            ]
          }
        ]
      }' | jq -r '.secret // empty'
  )
  if [[ -n "$ROBOT_PASS" ]]; then
    log "New robot created, saving credentials"
    echo "export ROBOT_PASS='$ROBOT_PASS'" > "$ROBOT_ENV"
    chmod 600 "$ROBOT_ENV"
  else
    echo "ERROR: Failed to create robot. Cannot register Argo CD repo."
    exit 1
  fi
fi

# 4. Register Harbor repo in Argo CD
log "Registering Harbor Helm OCI repo in Argo CD (via manifest)..."
# kubectl apply -f ArgoCD-demo-apps/argocd-repos/harbor-helm-repo.yaml
argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS" \
  --upsert

# 5. Local DNS convenience
grep -q "tekton.local" /etc/hosts || \
  echo "$METALLB_IP tekton.local" | sudo tee -a /etc/hosts >/dev/null

# 6. Deploy Tekton via ArgoCD (control plane: tekton-pipelines namespace)
log "Deploying Tekton control plane via ArgoCD..."
log "  - Tekton Pipelines → tekton-pipelines namespace (privileged)"
log "  - Using ghcr.io mirrors to avoid gcr.io auth issues"

kubectl apply -f "$ROOT_DIR/Tekton/project.yaml"
kubectl apply -f "$ROOT_DIR/Tekton/application.yaml"

log "Waiting for ArgoCD to sync Tekton application..."
for i in {1..60}; do
  SYNC_STATUS=$(kubectl get application tekton-pipelines -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  HEALTH_STATUS=$(kubectl get application tekton-pipelines -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  
  if [[ "$SYNC_STATUS" == "Synced" ]]; then
    log "ArgoCD application synced (Health: $HEALTH_STATUS)"
    break
  fi
  
  echo "  Waiting for sync... (Status: $SYNC_STATUS, Health: $HEALTH_STATUS) - attempt $i/60"
  sleep 5
done

log "Waiting for Tekton CRDs to be established..."
for i in {1..30}; do
  if kubectl get crd pipelines.tekton.dev >/dev/null 2>&1; then
    kubectl wait --for=condition=established --timeout=60s crd/pipelines.tekton.dev 2>/dev/null || true
    break
  fi
  echo "  CRD not yet created... attempt $i/30"
  sleep 3
done

log "Waiting for Tekton controllers to be ready..."
for i in {1..60}; do
  if kubectl get deployment tekton-pipelines-controller -n tekton-pipelines >/dev/null 2>&1; then
    kubectl wait --for=condition=available --timeout=60s \
      deployment/tekton-pipelines-controller -n tekton-pipelines 2>/dev/null && break
  fi
  echo "  Controller deployment not yet ready... attempt $i/60"
  sleep 5
done

for i in {1..60}; do
  if kubectl get deployment tekton-pipelines-webhook -n tekton-pipelines >/dev/null 2>&1; then
    kubectl wait --for=condition=available --timeout=60s \
      deployment/tekton-pipelines-webhook -n tekton-pipelines 2>/dev/null && break
  fi
  echo "  Webhook deployment not yet ready... attempt $i/60"
  sleep 5
done

log "Tekton Dashboard deployed via manifests (included in ArgoCD application)"

log "Applying Tekton HTTPRoute..."
kubectl apply -f "$ROOT_DIR/Tekton/tekton-dashboard-httproute.yaml"

# 7. Create tekton-builds namespace (execution environment with restricted security)
log "Creating tekton-builds namespace (pipeline execution environment)..."
log "  - Pod Security Admission: baseline (restricted security context)"
log "  - This is where PipelineRuns execute (separate from control plane)"

kubectl create namespace tekton-builds --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns tekton-builds \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite

# 8. Add Harbor registry secret to tekton-builds (execution namespace only)
log "Adding Harbor registry secret to tekton-builds..."
log "  - Scoped to execution namespace for security isolation"

kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

# 9. Deploy Tekton Pipeline resources to tekton-builds namespace
log "Deploying Tekton Pipelines, Tasks, and ServiceAccounts to tekton-builds..."
log "  - ServiceAccounts with restricted permissions"
log "  - Pipeline definitions"
log "  - Task definitions (clone, build-push, update-tag)"

kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/configs/tekton-sa.yaml"
kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/configs/tekton-sa-builds.yaml"
kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/tekton-pipeline.yaml"
kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/tekton-task-1-clone-repo.yaml"
kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/tekton-task-2-build-push.yaml"
kubectl apply -f "$ROOT_DIR/Tekton-Pipelines/tekton-task-3-update-tag.yaml"

# 10. Setup GitHub Deploy Key (for git push from tekton-builds)
log "Setting up GitHub Deploy Key in tekton-builds namespace..."
log "  - Used by update-tag task to push manifest changes"

DEPLOY_KEY_FILE="$HOME/.ssh/argoCD"
if [ -f "$DEPLOY_KEY_FILE" ]; then
  log "Using existing deploy key: $DEPLOY_KEY_FILE"
  
  # Create the deploy key secret in tekton-builds namespace
  kubectl create secret generic github-deploy-key \
    --from-file=ssh-privatekey="$DEPLOY_KEY_FILE" \
    --from-literal=known_hosts="$(ssh-keyscan github.com 2>/dev/null)" \
    -n tekton-builds \
    --dry-run=client -o yaml | kubectl apply -f -
else
  log "WARNING: Deploy key not found at $DEPLOY_KEY_FILE"
  log "Tekton pipelines will not be able to push image tags back to Git"
  log ""
  log "To create the key:"
  log "  ssh-keygen -t ed25519 -C 'argocd-deploy-key' -f $DEPLOY_KEY_FILE -N ''"
  log ""
  log "Then add the PUBLIC key to GitHub:"
  log "  cat ${DEPLOY_KEY_FILE}.pub"
  log "  → GitHub repo → Settings → Deploy keys → Add deploy key"
  log "  → Enable 'Allow write access'"
fi

log ""
log "✅ Tekton installation complete (GitOps via ArgoCD)"
log ""
log "Architecture:"
log "  Control Plane:  tekton-pipelines namespace (privileged)"
log "  Execution Env:  tekton-builds namespace (PSA baseline, restricted)"
log ""
log "Access:"
log "  Tekton Dashboard: https://tekton.local"
