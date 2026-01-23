#!/bin/bash
set -euo pipefail
# 13-prometheus - Prometheus + Grafana for Argo CD (GitOps-safe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 13: Observability (Prometheus + Grafana) – Artifact & GitOps setup"

cd "$ROOT_DIR"

# 1. Package Prometheus Helm chart
log "Packaging and pushing Prometheus Helm chart to Harbor..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update >/dev/null

helm pull prometheus-community/prometheus --version 28.6.0

# 2. Ensure Harbor project exists
log "Ensuring Harbor project 'helm' exists..."

curl -sk -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{"project_name":"helm","public":false}' || true

# 3. Push Helm chart to Harbor OCI repo
helm push prometheus-28.6.0.tgz oci://harbor.local/helm || true

# 4. Create / load Harbor robot account (system-level, no project_id needed)
log "Ensuring Harbor robot account for Argo CD..."

ROBOT_ENV="$ROOT_DIR/.harbor-robot-pass.env"

# Delete existing robot if present (to get fresh credentials)
EXISTING_ROBOT_ID=$(curl -sk -u admin:Harbor12345 \
  "https://harbor.local/api/v2.0/robots?q=name%3Dargocd" | jq -r '.[0].id // empty')
if [[ -n "$EXISTING_ROBOT_ID" ]]; then
  log "Deleting existing robot (id: $EXISTING_ROBOT_ID)..."
  curl -sk -u admin:Harbor12345 -X DELETE "https://harbor.local/api/v2.0/robots/$EXISTING_ROBOT_ID"
fi

NEW_ROBOT_PASS=$(
  curl -sk -u admin:Harbor12345 \
    -X POST https://harbor.local/api/v2.0/robots \
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

if [[ -n "$NEW_ROBOT_PASS" ]]; then
  log "New robot created, saving credentials"
  echo "export ROBOT_PASS='$NEW_ROBOT_PASS'" > "$ROBOT_ENV"
  chmod 600 "$ROBOT_ENV"
fi

source "$ROBOT_ENV" || {
  echo "ERROR: Robot credentials missing. Delete and recreate robot."
  exit 1
}

# 5. Register Harbor repo in Argo CD (OCI)
log "Registering Harbor Helm OCI repo in Argo CD..."

argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS" \
  || true

# 6. Local DNS convenience
grep -q "grafana.local" /etc/hosts || \
  echo "$METALLB_IP grafana.local" | sudo tee -a /etc/hosts >/dev/null

log "Prometheus stack artifact ready"
log "Next step: create Argo CD Application for kube-prometheus-stack"
log "Step 13 complete."
