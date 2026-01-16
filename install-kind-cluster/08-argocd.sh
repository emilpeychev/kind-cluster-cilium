#!/usr/bin/env bash
set -euo pipefail
# 08-argocd.sh - Install ArgoCD and deploy applications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 8: Install ArgoCD"

require_cmd argocd

cd "$ROOT_DIR"

# Add /etc/hosts entries
grep -q "argocd.local" /etc/hosts || echo "$METALLB_IP argocd.local" | sudo tee -a /etc/hosts
grep -q "demo-app1.local" /etc/hosts || echo "$METALLB_IP demo-app1.local" | sudo tee -a /etc/hosts

# Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Apply custom configurations via Kustomize
kubectl apply -k ArgoCD/
sleep 1
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd
sleep 10

# Login and add repository
log "Logging into ArgoCD and adding repository"
NS=argocd
SERVER=argocd.local
SSH_KEY="$HOME/.ssh/argoCD"
REPO="git@github.com:emilpeychev/kind-cluster-cilium.git"

PASSWORD="$(kubectl -n "$NS" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

argocd login "$SERVER" \
  --username admin \
  --password "$PASSWORD" \
  --grpc-web \
  --insecure

# Add Git SSH host to known_hosts
HOST=github.com
ssh-keygen -F "$HOST" >/dev/null 2>&1 || ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts

# Add Git repository
argocd repo add "$REPO" \
  --ssh-private-key-path "$SSH_KEY" \
  --grpc-web

# Install ArgoCD Image Updater
log "Installing ArgoCD Image Updater..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v0.15.1/manifests/install.yaml

# Configure Image Updater for Harbor
kubectl apply -f ArgoCD-Image-Updater/image-updater-config.yaml

log "Waiting for ArgoCD Image Updater..."
kubectl wait --for=condition=available --timeout=120s deployment/argocd-image-updater -n argocd || true

# Build and push initial demo-app image to Harbor
log "Building and pushing initial demo-app image to Harbor..."
if command -v docker &> /dev/null; then
  docker build -t harbor.local/library/demo-app:latest demo-app/ 2>/dev/null || {
    echo "WARNING: Could not build demo-app image. Skipping initial image push."
  }
  
  docker push harbor.local/library/demo-app:latest 2>/dev/null || {
    echo "INFO: Docker push failed (CA not trusted). Triggering Tekton build instead..."
    
    cat <<'PIPELINERUN' | kubectl create -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: initial-build-
  namespace: tekton-builds
spec:
  pipelineRef:
    name: clone-build-push
  params:
    - name: GIT_URL
      value: "https://github.com/emilpeychev/kind-cluster-cilium.git"
    - name: GIT_BRANCH
      value: "master"
    - name: IMAGE_REPO
      value: "harbor.local/library/demo-app"
    - name: VERSION
      value: "latest"
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
    - name: ssh-creds
      secret:
        secretName: github-deploy-key
  taskRunTemplate:
    serviceAccountName: tekton-build-sa
PIPELINERUN
    log "Initial Tekton build triggered. Waiting for completion..."
    sleep 10
    kubectl wait --for=condition=Succeeded --timeout=300s \
      pipelinerun -l tekton.dev/pipeline=clone-build-push -n tekton-builds || {
        echo "WARNING: Initial build may still be running. Check with: kubectl get pipelineruns -n tekton-builds"
      }
  }
fi

# Deploy ArgoCD Project and ApplicationSet
kubectl apply -f ArgoCD-demo-apps/projects/application-sets-projects.yaml
kubectl apply -f ArgoCD-demo-apps/applicationsets/application-sets.yaml
kubectl apply -k ArgoCD-demo-apps/apps/

log "Waiting for ArgoCD Applications to be created..."
sleep 10

# Show ArgoCD Applications status
kubectl get applications -n argocd

# Deploy GitHub polling CronJob
log "Deploying GitHub polling trigger..."
kubectl apply -f Tekton-Pipelines/tekton-trigger-cronjob.yaml

# Initialize with current commit
log "Initializing poll state with current commit..."
CURRENT_COMMIT=$(curl -s "https://api.github.com/repos/emilpeychev/kind-cluster-cilium/commits/master" | grep -m1 '"sha"' | cut -d'"' -f4)
if [ -n "$CURRENT_COMMIT" ]; then
  kubectl patch configmap github-poll-state -n tekton-builds \
    --type merge -p '{"data":{"last-commit":"'"${CURRENT_COMMIT}"'"}}' || true
  log "Poll state initialized to commit: ${CURRENT_COMMIT}"
fi

log "ArgoCD installed successfully"
echo "ArgoCD URL: https://argocd.local"
echo "Admin password: $PASSWORD"
