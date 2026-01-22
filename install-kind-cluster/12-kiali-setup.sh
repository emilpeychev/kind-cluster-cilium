#!/usr/bin/env bash
set -euo pipefail
# 12-kiali - Deploy additional applications via manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 12: Observability Kiali Setup"

cd "$ROOT_DIR"
# Deploy Kiali via Helm chart in Harbor
log "Packaging and pushing Kiali Helm chart to Harbor..."
helm repo add kiali https://kiali.org/helm-charts
helm repo update
helm pull kiali/kiali-server --version 2.20.0
helm push kiali-server-2.20.0.tgz oci://harbor.local/helm

# Create harbor project 'helm' if not exists
log "Creating Harbor project 'helm'..."
curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"helm","public":false}' || true

# Create Harbor robot account

log "Creating Harbor robot account..."#!/usr/bin/env bash
set -euo pipefail
# 12-kiali - Publish Kiali Helm chart and register it for Argo CD (GitOps-safe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 12: Observability (Kiali) – Artifact & GitOps setup"

cd "$ROOT_DIR"

# 1. Package & push Kiali Helm chart
log "Packaging and pushing Kiali Helm chart to Harbor..."

helm repo add kiali https://kiali.org/helm-charts >/dev/null
helm repo update >/dev/null

helm pull kiali/kiali-server --version 2.20.0
helm push kiali-server-2.20.0.tgz oci://harbor.local/helm || true

# 2. Ensure Harbor project exists
log "Ensuring Harbor project 'helm' exists..."

curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"helm","public":false}' || true

# 3. Create Harbor robot account
log "Creating Harbor robot account for Argo CD..."

ROBOT_PASS=$(
  curl -sk -u admin:Harbor12345 \
    -X POST "https://harbor.local/api/v2.0/robots" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "argocd",
      "level": "project",
      "project_id": 2,
      "duration": -1,
      "permissions": [
        {
          "kind": "project",
          "namespace": "helm",
          "access": [
            { "resource": "repository", "action": "pull" }
          ]
        }
      ]
    }' | jq -r '.secret // empty'
)

if [[ -z "$ROBOT_PASS" ]]; then
  log "Robot already exists. Recreate it if credentials are lost."
  exit 0
fi

# 4. Register Harbor repo in Argo CD

log "Registering Harbor Helm OCI repo in Argo CD..."

argocd repo add harbor.local/helm \
  --type helm \
  --name kiali \
  --enable-oci \
  --username robot\$helm+argocd \
  --password "$ROBOT_PASS" \
  --insecure-skip-server-verification || true


# 5. Local DNS convenience


grep -q "kiali.local" /etc/hosts || \
  echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts >/dev/null

# 6. Hand off to GitOps
log "Kiali will be deployed by Argo CD"
log "Check status with: kubectl get applications -n argocd"
log "URL (once synced): https://kiali.local"
# Create Harbor robot account for Argo CD
ROBOT_PASS=$(
  curl -sk -u admin:Harbor12345 \
    -X POST "https://harbor.local/api/v2.0/robots" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "argocd",
      "level": "project",
      "project_id": 2,
      "duration": -1,
      "permissions": [
        {
          "kind": "project",
          "namespace": "helm",
          "access": [
            { "resource": "repository", "action": "pull" }
          ]
        }
      ]
    }' | jq -r '.secret'
)

echo "Robot password: $ROBOT_PASS"

# Register Harbor Helm OCI repo in Argo CD
log "Registering Harbor Helm OCI repo in Argo CD..."

argocd repo add harbor.local/helm \
  --type helm \
  --name kiali \
  --enable-oci \
  --username robot\$helm+argocd \
  --password "$ROBOT_PASS" \
  --insecure-skip-server-verification

# DNS entry for Kiali (MetalLB)
grep -q "kiali.local" /etc/hosts || echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts


# Verify deployments
log "Verifying deployments..."
kubectl get deployments -n kiali
echo "Kiali:       https://kiali.local"
echo ""
echo "Test Kiali: curl -k https://kiali.local/get"