#!/bin/bash
set -euo pipefail
# 12-kiali - Publish Kiali Helm chart and register it for Argo CD (GitOps-safe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 12: Observability (Kiali) – Artifact & GitOps setup"

cd "$ROOT_DIR"

# 1. Package kiali Helm chart
log "Packaging and pushing Kiali Helm chart to Harbor..."

helm repo add kiali https://kiali.org/helm-charts >/dev/null
helm repo update >/dev/null
helm pull kiali/kiali-server --version 2.20.0

# 2. Ensure Harbor project exists
log "Ensuring Harbor project 'helm' exists..."

curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"helm","public":false}' || true

# Push Helm chart to Harbor OCI repo
helm push kiali-server-2.20.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f kiali-server-2.20.0.tgz

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
# kubectl apply -f observability-tools/kiali/addrepo-argcd.yaml
argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS" \
  --upsert

# 5. Local DNS convenience
grep -q "kiali.local" /etc/hosts || \
  echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts >/dev/null

# 6. Apply Kiali Argo CD manifests (project, application, httproute)
log "Applying Kiali Argo CD application..."

# Create kiali namespace if it doesn't exist
kubectl create namespace kiali 2>/dev/null || true

# Apply kiali manifests
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/project.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/application.yaml"
kubectl apply -f "$ROOT_DIR/observability-tools/kiali/httproute.yaml"

log "Waiting for Argo CD application to sync..."
sleep 5

# Show application status
kubectl get applications -n argocd kiali 2>/dev/null || true

log "Kiali deployed via Argo CD"
log "URL: https://kiali.local"
log "Step 12 complete."