#!/usr/bin/env bash
set -euo pipefail
# 05-tls-certs.sh - Generate TLS certificates and configure CoreDNS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

log "Step 5: TLS Certificates and CoreDNS"

cd "$ROOT_DIR"

# Create local CA if it doesn't exist
log "Creating a local Certificate Authority (CA)"
if [[ ! -f tls/ca.key || ! -f tls/ca.crt ]]; then
  log "Creating local CA (first run)"
  openssl genrsa -out tls/ca.key 4096
  openssl req -x509 -new -nodes \
    -key tls/ca.key \
    -sha256 -days 365 \
    -out tls/ca.crt \
    -subj "/CN=Local Dev CA"
else
  log "Local CA already exists, reusing it"
fi

# Generate gateway CSR and key
openssl req -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout tls/key.pem \
  -out tls/gateway.csr \
  -config tls/openssl-local.cnf

# Sign the gateway cert with CA
log "Signing the gateway certificate with CA"
openssl x509 -req \
  -in tls/gateway.csr \
  -CA tls/ca.crt \
  -CAkey tls/ca.key \
  -CAcreateserial \
  -out tls/cert.pem \
  -days 365 \
  -sha256 \
  -extensions req_ext \
  -extfile tls/openssl-local.cnf

# Verify certificate
log "Verifying certificate"
openssl x509 -in tls/cert.pem -noout -text | grep -A2 "Subject Alternative Name"
openssl verify -CAfile tls/ca.crt tls/cert.pem

echo ""
echo "================================================"
echo "To trust the local CA on your machine, run:"
echo "================================================"
echo "sudo cp tls/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt"
echo "sudo update-ca-certificates"
echo "================================================"
echo ""

sleep 3

# Create TLS secret
kubectl create secret tls istio-gateway-credentials \
  --cert=tls/cert.pem \
  --key=tls/key.pem \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -

log "TLS secret created in istio-gateway namespace"

# Patch CoreDNS
log "Patching CoreDNS to resolve *.local domains"

GATEWAY_IP=$(kubectl get svc istio-gateway-istio \
  -n istio-gateway \
  -o jsonpath='{.spec.clusterIP}')

if [[ -z "${GATEWAY_IP}" ]]; then
  echo "ERROR: istio-gateway-istio ClusterIP not found" >&2
  exit 1
fi

kubectl get configmap coredns -n kube-system -o json | \
jq --arg ip "$GATEWAY_IP" '
  .data.Corefile = ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    hosts {\n        " + $ip + " harbor.local argocd.local tekton.local demo-app1.local webhooks.local workflows.local\n        fallthrough\n    }\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf {\n       max_concurrent 1000\n    }\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
' | kubectl apply -f -

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

log "CoreDNS patched - *.local domains now resolve inside the cluster"
