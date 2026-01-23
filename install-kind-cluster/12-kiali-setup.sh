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

# 3. Create Harbor robot account (system-level, no project_id needed)
log "Creating Harbor robot account for Argo CD..."

# Delete existing robot if present (to get fresh credentials)
EXISTING_ROBOT_ID=$(curl -sk -u admin:Harbor12345 \
  "https://harbor.local/api/v2.0/robots?q=name%3Dargocd" | jq -r '.[0].id // empty')
if [[ -n "$EXISTING_ROBOT_ID" ]]; then
  log "Deleting existing robot (id: $EXISTING_ROBOT_ID)..."
  curl -sk -u admin:Harbor12345 -X DELETE "https://harbor.local/api/v2.0/robots/$EXISTING_ROBOT_ID"
fi

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
            { "resource": "artifact", "action": "read" }
          ]
        }
      ]
    }' | jq -r '.secret // empty'
)

if [[ -n "$ROBOT_PASS" ]]; then
  log "New robot created, saving credentials"
  echo "export ROBOT_PASS='$ROBOT_PASS'" > "$ROOT_DIR/.harbor-robot-pass.env"
  chmod 600 "$ROOT_DIR/.harbor-robot-pass.env"
else
  log "Robot already exists, loading existing credentials"
  source "$ROOT_DIR/.harbor-robot-pass.env"
fi

if [[ -z "${ROBOT_PASS:-}" ]]; then
  echo "ERROR: ROBOT_PASS is empty. Cannot register Argo CD repo."
  exit 1
fi


# 4. Register Harbor repo in Argo CD
log "Registering Harbor Helm OCI repo in Argo CD (via manifest)..."
# kubectl apply -f observability-tools/kiali/addrepo-argcd.yaml
argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS"

# 5. Local DNS convenience
grep -q "kiali.local" /etc/hosts || \
  echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts >/dev/null

# 6. Hand off to GitOps
log "Kiali will be deployed by Argo CD"
log "Check status with: kubectl get applications -n argocd"
log "URL (once synced): https://kiali.local"


# DNS entry for Kiali (MetalLB)
grep -q "kiali.local" /etc/hosts || echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts

# Verify deployments
log "Verifying deployments..."
kubectl get deployments -n kiali
log "Kiali:       https://kiali.local"
log "Step 12 complete."