#!/usr/bin/env bash
set -euo pipefail
# This script sets up a local Kubernetes cluster using kind with Cilium CNI, MetalLB for load balancing, and Istio in ambient mode.
KIND_SUBNET="172.20.0.0/16"
METALLB_POOL="172.20.255.200-172.20.255.250"

echo "==> Ensuring Docker 'kind' network exists"

if docker network inspect kind >/dev/null 2>&1; then
  echo "==> Docker 'kind' network already exists"
else
  docker network create kind --subnet "${KIND_SUBNET}"
fi


docker network inspect kind | grep Subnet || true

# Create kind cluster

echo "==> Creating kind cluster"
kind create cluster --config=kind-config.yaml

sleep 5
# Install MetalLB
echo "==> Installing MetalLB (native)"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

sleep 5
# Install Cilium CNI
echo "==> Installing Cilium"
cilium install \
  --version 1.18.4 \
  --set kubeProxyReplacement=true \
  --set kubeProxyReplacementMode=strict \
  --set cni.exclusive=false \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.244.0.0/16 \
  --set k8s.requireIPv4PodCIDR=true

cilium status --wait

sleep 30
# Configure MetalLB L2 pool
echo "==> Configuring MetalLB L2 pool"
kubectl apply -f metalLB/metallb-config.yaml

sleep 5
# Install Gateway API CRDs
echo "==> Installing Gateway API CRDs"
kubectl apply --server-side -f \
https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

sleep 5
# Create istio-gateway namespace
echo "==> Creating istio-gateway namespace (ambient)"
kubectl create namespace istio-gateway --dry-run=client -o yaml | kubectl apply -f -
# Label namespace for ambient mode data plane operation
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient --overwrite
sleep 2

# #####################################################
# #Option 1: Self-signed certs for local-dev use only
# #####################################################
# # Generate TLS key and cert
# echo "==> Generating TLS key and cert for Istio Gateway"
# sleep 2

# openssl req -x509 -nodes -days 365 \
#   -newkey rsa:2048 \
#   -keyout tls/key.pem \
#   -out tls/cert.pem \
#   -config tls/openssl-local.cnf \
#   -extensions req_ext

# sleep 2

# # Create TLS secret
# echo "==> Creating TLS secret for Istio Gateway"
# kubectl create secret tls istio-gateway-credentials \
#   --cert=tls/cert.pem \
#   --key=tls/key.pem \
#   -n istio-gateway \
#   --dry-run=client -o yaml | kubectl apply -f -

# openssl x509 -in tls/cert.pem -noout -text | grep -A2 "Subject Alternative Name"
# sleep 5


# Install Istio Ambient
echo "==> Installing Istio Ambient"
istioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway' \
  --skip-confirmation

sleep 10

echo "==> Creating a local Certificate Authority (CA)"
echo "This CA is only for your machine."
sleep 2

if [[ ! -f tls/ca.key || ! -f tls/ca.crt ]]; then
  echo "==> Creating local CA (first run)"
  openssl genrsa -out tls/ca.key 4096
  openssl req -x509 -new -nodes \
    -key tls/ca.key \
    -sha256 -days 365 \
    -out tls/ca.crt \
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
  -keyout tls/key.pem \
  -out tls/gateway.csr \
  -config tls/openssl-local.cnf

echo "***Gateway CSR created***"
echo "Files generated:"
echo "ca.key → your CA private key (keep this safe!)"  
echo "ca.crt → your CA certificate (to be trusted by your OS)"
sleep 2

echo "Step 3 — Sign the gateway cert with your CA"

echo "==> Signing the gateway certificate with your CA"

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

openssl x509 -in tls/cert.pem -noout -text | grep -A2 "Subject Alternative Name"


echo "***Expected:***"

echo "  DNS:*.local, DNS:localhost"
echo "Verify that cert.pem is signed by your CA (ca.crt):"

openssl verify -CAfile tls/ca.crt tls/cert.pem

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
  --cert=tls/cert.pem \
  --key=tls/key.pem \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -
echo "***TLS secret created in istio-gateway namespace***"
sleep 5
kubectl rollout restart deployment/istio-ingressgateway -n istio-gateway
sleep 10

# Apply Gateway and Routes
echo "==> Applying Gateway + Routes"
kubectl apply -f gateway.yaml

# sleep 10
# # Apply httpbin application and HTTPRoute
# echo "==> Applying httpbin application and HTTPRoute"
# kubectl apply -f httpbin.yaml
# kubectl apply -f httproute-httpbin.yaml


echo
echo "================================================"
echo "✔ Cluster setup complete"
echo "================================================"

kubectl get svc -n istio-gateway

echo
echo "================================================"
echo "* Setup Harbor URL: https://harbor.local"
echo "================================================"

# Add entry to /etc/hosts
grep -q "harbor.local" /etc/hosts || echo "172.20.255.201 harbor.local" | sudo tee -a /etc/hosts

helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor --version 1.18.1 \
  --create-namespace \
  -n harbor \
  -f Harbor/harbor-values.yaml

# Wait for Harbor to be ready
kubectl wait --for=condition=available --timeout=300s deployment/harbor-core -n harbor

# Create Harbor TLS secrets
kubectl create secret tls harbor-tls \
  --cert=tls/cert.pem \
  --key=tls/key.pem \
  -n harbor --dry-run=client -o yaml | kubectl apply -f -

# Create CA certificate ConfigMap for the installer
kubectl create configmap harbor-ca-cert \
  --from-file=ca.crt=tls/ca.crt \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Apply Harbor CA installer
kubectl apply -f Harbor/harbor-ca-installer.yaml

kubectl apply -f Harbor/harbor-httproute.yaml

echo "================================================"
echo "* Setup Tekton Pipelines: https://tekton.local"
echo "================================================"

# /etc/hosts
grep -q "tekton.local" /etc/hosts || echo "172.20.255.201 tekton.local" | sudo tee -a /etc/hosts

# Install Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for controller
kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

# Wait for CRDs
kubectl wait --for=condition=established --timeout=120s crd/pipelines.tekton.dev

echo "==> Waiting for Tekton controller + webhook to be ready"

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-webhook -n tekton-pipelines

echo "==> Waiting for Tekton webhook service endpoints"
until kubectl -n tekton-pipelines get endpoints tekton-pipelines-webhook \
  -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -qE '^[0-9]'; do
  echo "  ...still waiting for endpoints"
  sleep 2
done

echo "==> Enabling Tekton securityContext support (with retry)"
for i in {1..30}; do
  if kubectl patch configmap feature-flags -n tekton-pipelines \
    --type merge \
    -p '{"data":{"set-security-context":"true"}}'; then
    echo "✅ Patched feature-flags"
    break
  fi
  echo "  patch failed (webhook not reachable yet). retry $i/30..."
  sleep 2
done

# Install Tekton Dashboard
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml
kubectl apply -f Tekton/tekton-dashboard-httproute.yaml

sleep 5

echo "================================================"
echo " Create tekton-builds namespace (PSA baseline)"
echo "================================================"

kubectl create namespace tekton-builds --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns tekton-builds \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite
sleep 5

echo "================================================"
echo " Add Harbor registry secret to tekton-builds"
echo "================================================"

kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor-core.harbor.svc.cluster.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

sleep 1
# Apply Tekton Pipeline resources
kubectl apply -f Tekton-Pipelines/configs/
sleep 1

echo "================================================"
echo "* Setup ArgoCD URL: https://argocd.local"
echo "================================================"
# Add entry to /etc/hosts
grep -q "argocd.local" /etc/hosts || echo "172.20.255.201 argocd.local" | sudo tee -a /etc/hosts
# 1. Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 3. Apply custom configurations via Kustomize
kubectl apply -k ArgoCD
sleep 1
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd
sleep 10

# 4. Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 5. Add repositories for Git and Helm charts
cat > /tmp/argocd-login.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

NS=${ARGOCD_NAMESPACE:-argocd}
SERVER=${ARGO_SERVER:-argocd.local}
SSH_KEY=${ARGOCD_SSH_KEY:-$HOME/.ssh/id_ed25519}
REPO=${ARGOCD_REPO:-git@github.com:emilpeychev/kind-cluster-cilium.git}

# Get initial admin password
PASSWORD="$(kubectl -n "$NS" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

# Login via Gateway (grpc-web required behind Istio Gateway)
argocd login "$SERVER" \
  --username admin \
  --password "$PASSWORD" \
  --grpc-web \
  --insecure

# Add Git SSH host to known_hosts
HOST=github.com
ssh-keygen -F "$HOST" >/dev/null || ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts
# This checks if the github.com key is already present, if not it adds it.

# Add Git repository (grpc-web required again)
argocd repo add "$REPO" \
  --ssh-private-key-path "$SSH_KEY" \
  --grpc-web
EOF

chmod +x /tmp/argocd-login.sh
/tmp/argocd-login.sh
echo "================================================"
echo "* ArgoCD setup complete. Access it at: https://argocd.local"
echo "================================================"