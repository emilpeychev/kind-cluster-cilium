#!/bin/bash
set -euo pipefail
# 12-harbor-helm-charts - Publish all Helm charts to Harbor OCI registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

METALLB_IP="${METALLB_IP:-172.20.255.200}"

log "Step 12: Helm Charts – Publishing to Harbor OCI registry"

cd "$ROOT_DIR"

# 1. Package and push Kiali Helm chart
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

# Login to Harbor for helm push
echo "Harbor12345" | helm registry login harbor.local -u admin --password-stdin

# Push Helm chart to Harbor OCI repo
helm push kiali-server-2.20.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f kiali-server-2.20.0.tgz

# 2. Package and push Prometheus Helm chart
log "Packaging and pushing Prometheus Helm chart to Harbor..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm pull prometheus-community/prometheus --version 28.6.0

# Push Helm chart to Harbor OCI repo
helm push prometheus-28.6.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f prometheus-28.6.0.tgz

# 3. Package and push Grafana Helm chart
log "Packaging and pushing Grafana Helm chart to Harbor..."

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm pull grafana/grafana --version 10.5.12

# Push Helm chart to Harbor OCI repo
helm push grafana-10.5.12.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f grafana-10.5.12.tgz

# 4. Package and push Kyverno Helm chart
log "Packaging and pushing Kyverno Helm chart to Harbor..."

helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
helm pull kyverno/kyverno --version 3.7.0

# Push Helm chart to Harbor OCI repo
helm push kyverno-3.7.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f kyverno-3.7.0.tgz

# 5. Package and push Metrics Server Helm chart
log "Packaging and pushing Metrics Server Helm chart to Harbor..."

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null
helm pull metrics-server/metrics-server --version 3.13.0

# Push Helm chart to Harbor OCI repo
helm push metrics-server-3.13.0.tgz oci://harbor.local/helm || true

# Clean up downloaded chart
rm -f metrics-server-3.13.0.tgz

# 6. Create / load Harbor robot account (system-level)
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


# 7. Register Harbor repo in Argo CD
log "Registering Harbor Helm OCI repo in Argo CD..."

argocd repo add harbor.local \
  --type helm \
  --name harbor-helm \
  --enable-oci \
  --username 'robot$argocd' \
  --password "$ROBOT_PASS" \
  --upsert

# Also create/update the repository Secret in argocd namespace
source "$ROOT_DIR/.harbor-robot-pass.env" || true
kubectl create secret generic harbor-helm-repo -n argocd \
  --from-literal=url=https://harbor.local \
  --from-literal=username='robot$argocd' \
  --from-literal=password="$ROBOT_PASS" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label secret harbor-helm-repo -n argocd argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

# 8. Local DNS convenience
grep -q "kiali.local" /etc/hosts || \
  echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts >/dev/null
grep -q "prometheus.local" /etc/hosts || \
  echo "$METALLB_IP prometheus.local" | sudo tee -a /etc/hosts >/dev/null
grep -q "grafana.local" /etc/hosts || \
  echo "$METALLB_IP grafana.local" | sudo tee -a /etc/hosts >/dev/null

log "Helm charts published to Harbor OCI registry"
log "Charts available at: oci://harbor.local/helm/{kiali-server,prometheus,grafana,kyverno,metrics-server}"
log "Step 12 complete."