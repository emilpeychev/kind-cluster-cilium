#!/usr/bin/env bash
set -euo pipefail
# 14-kyverno.sh - Deploy Kyverno via Argo CD and apply image verification policy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 14: Kyverno Policy Engine – Deploying via Argo CD"

cd "$ROOT_DIR"

# ── 1. Deploy Kyverno via Argo CD ────────────────────────────────────
log "Applying Argo CD project and application for Kyverno..."

kubectl apply -f "$ROOT_DIR/Kyverno/project.yaml"
kubectl apply -f "$ROOT_DIR/Kyverno/application.yaml"

log "Waiting for Argo CD to sync Kyverno..."
sleep 10

# Wait for Kyverno admission controller to be ready
RETRIES=0
MAX_RETRIES=60
until kubectl get deployment kyverno-admission-controller -n kyverno &>/dev/null && \
      kubectl wait --for=condition=available --timeout=10s \
        deployment/kyverno-admission-controller -n kyverno &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    echo "ERROR: Kyverno admission controller not ready after ${MAX_RETRIES} attempts."
    echo "Check ArgoCD application status: kubectl get applications -n argocd kyverno"
    exit 1
  fi
  echo "  ...waiting for Kyverno (attempt $RETRIES/$MAX_RETRIES)"
  sleep 10
done

log "Kyverno is ready"

# ── 2. Extract cosign public key from Tekton secret ─────────────────
log "Extracting cosign public key from tekton-builds/cosign-key secret..."

RETRIES=0
MAX_RETRIES=30
until kubectl get secret cosign-key -n tekton-builds &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    echo "ERROR: cosign-key secret not found in tekton-builds namespace."
    echo "Please run step 7 (Tekton) first to generate cosign keys."
    exit 1
  fi
  echo "  ...waiting for cosign-key secret (attempt $RETRIES/$MAX_RETRIES)"
  sleep 5
done

COSIGN_PUB=$(kubectl get secret cosign-key -n tekton-builds \
  -o jsonpath='{.data.cosign\.pub}' | base64 -d)

if [[ -z "$COSIGN_PUB" ]]; then
  echo "ERROR: cosign public key is empty"
  exit 1
fi

log "Cosign public key extracted successfully"

# ── 3. Inject public key into policy and apply ───────────────────────
log "Deploying image verification policy..."

POLICY_FILE="$ROOT_DIR/Kyverno/verify-image-policy.yaml"
TEMP_POLICY=$(mktemp)

# Replace placeholder with real cosign public key
sed "s|-----BEGIN PUBLIC KEY-----.*-----END PUBLIC KEY-----|PLACEHOLDER_BLOCK|" "$POLICY_FILE" > "$TEMP_POLICY"

KEY_BLOCK=$(echo "$COSIGN_PUB" | sed 's/^/                      /')
awk -v key="$KEY_BLOCK" '{
  if ($0 ~ /PLACEHOLDER_BLOCK/) {
    print key
  } else {
    print
  }
}' "$TEMP_POLICY" > "${TEMP_POLICY}.2"
mv "${TEMP_POLICY}.2" "$TEMP_POLICY"

sed -i '/REPLACE_WITH_COSIGN_PUBLIC_KEY/d' "$TEMP_POLICY"

kubectl apply -f "$TEMP_POLICY"
rm -f "$TEMP_POLICY"

log "Image verification policy applied"

# ── 4. Apply policy exceptions for system namespaces ─────────────────
log "Applying policy exceptions for infrastructure namespaces..."
kubectl apply -f "$ROOT_DIR/Kyverno/policy-exceptions.yaml"

# ── 5. Verify installation ───────────────────────────────────────────
log "Verifying Kyverno installation..."
kubectl get clusterpolicy verify-signed-images
kubectl get pods -n kyverno
kubectl get applications -n argocd kyverno

log "Kyverno deployed via Argo CD successfully"
log "Policy: verify-signed-images (Enforce mode)"
log "Scope:  harbor.local/library/* images in demo-apps namespace"
log ""
log "Unsigned images will be REJECTED in the demo-apps namespace."
log "All infrastructure namespaces are excluded via PolicyException."
