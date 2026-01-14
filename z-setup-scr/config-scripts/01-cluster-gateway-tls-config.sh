#!/usr/bin/env bash
set -euo pipefail
# Part 1 - Config: Cluster, Gateways, and TLS configuration
# This script configures TLS certificates and CoreDNS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "==> Creating a local Certificate Authority (CA)"
echo "This CA is only for your machine."
sleep 2

if [[ ! -f "${REPO_ROOT}/tls/ca.key" || ! -f "${REPO_ROOT}/tls/ca.crt" ]]; then
  echo "==> Creating local CA (first run)"
  openssl genrsa -out "${REPO_ROOT}/tls/ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "${REPO_ROOT}/tls/ca.key" \
    -sha256 -days 365 \
    -out "${REPO_ROOT}/tls/ca.crt" \
    -subj "/CN=Local Dev CA"
else
  echo "==> Local CA already exists, reusing it"
fi

echo "***This is the root of trust***"
echo "- Keep it private"
echo "- Never commit it"
sleep 2

echo "***CA created***"

openssl req -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout "${REPO_ROOT}/tls/key.pem" \
  -out "${REPO_ROOT}/tls/gateway.csr" \
  -config "${REPO_ROOT}/tls/openssl-local.cnf"

echo "***Gateway CSR created***"
echo "Files generated:"
echo "ca.key → your CA private key (keep this safe!)"  
echo "ca.crt → your CA certificate (to be trusted by your OS)"
sleep 2

echo "Step 3 — Sign the gateway cert with your CA"

echo "==> Signing the gateway certificate with your CA"

openssl x509 -req \
  -in "${REPO_ROOT}/tls/gateway.csr" \
  -CA "${REPO_ROOT}/tls/ca.crt" \
  -CAkey "${REPO_ROOT}/tls/ca.key" \
  -CAcreateserial \
  -out "${REPO_ROOT}/tls/cert.pem" \
  -days 365 \
  -sha256 \
  -extensions req_ext \
  -extfile "${REPO_ROOT}/tls/openssl-local.cnf"
sleep 2

echo "***Gateway certificate signed by your CA***"
echo "Files generated:"
echo "  
cert.pem → gateway certificate signed by your CA
cert.pem is NOT self-signed
It is signed by your CA

SANs still apply (*.local, localhost)"

sleep 2

echo "==> Step 4 — Verify (always verify)"

openssl x509 -in "${REPO_ROOT}/tls/cert.pem" -noout -text | grep -A2 "Subject Alternative Name"

echo "***Expected:***"
echo "  DNS:*.local, DNS:localhost"
echo "Verify that cert.pem is signed by your CA (ca.crt):"

openssl verify -CAfile "${REPO_ROOT}/tls/ca.crt" "${REPO_ROOT}/tls/cert.pem"

echo "***Expected:***"
echo "tls/cert.pem: OK"

echo "Step 5 — Trust the CA on your machine"

echo "This is what removes the prompt."

echo "***On Linux (most distros)***"  
echo "Run the following commands with sudo privileges:" 

cat <<'EOF'

================================================
To trust the local CA on your machine, run:
================================================

sudo cp tls/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt
sudo update-ca-certificates

After this:
- Your OS will trust certificates signed by this CA
- Browsers, curl, and CLIs will stop showing TLS warnings

================================================
EOF
echo "Proceeding in 5 seconds..."
sleep 5

kubectl create secret tls istio-gateway-credentials \
  --cert="${REPO_ROOT}/tls/cert.pem" \
  --key="${REPO_ROOT}/tls/key.pem" \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -
echo "***TLS secret created in istio-gateway namespace***"
sleep 5
kubectl rollout restart deployment/istio-ingressgateway -n istio-gateway
sleep 10

# Apply Gateway and Routes
echo "==> Applying Gateway + Routes"
kubectl apply -f "${REPO_ROOT}/gateway.yaml"

# Patch CoreDNS to resolve *.local domains inside the cluster
echo "==> Patching CoreDNS to resolve *.local domains"

GATEWAY_IP=$(kubectl get svc istio-gateway-istio \
  -n istio-gateway \
  -o jsonpath='{.spec.clusterIP}')

if [[ -z "${GATEWAY_IP}" ]]; then
  echo "ERROR: istio-gateway-istio ClusterIP not found"
  exit 1
fi

kubectl get configmap coredns -n kube-system -o json | \
jq --arg ip "$GATEWAY_IP" '
  .data.Corefile = ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    hosts {\n        " + $ip + " harbor.local argocd.local tekton.local demo-app1.local\n        fallthrough\n    }\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf {\n       max_concurrent 1000\n    }\n    cache 30\n    loop\n    reload\n    loadbalance\n}"
' | kubectl apply -f -

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

echo "==> CoreDNS patched - *.local domains now resolve inside the cluster"

echo
echo "================================================"
echo "✔ Part 1 Config complete - Cluster configured"
echo "================================================"

kubectl get svc -n istio-gateway

echo "Next: Run setup-scripts/02-harbor-install.sh"
