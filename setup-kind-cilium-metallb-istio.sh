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

# HARD wait for dataplane convergence
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=cilium --timeout=5m
kubectl wait --for=condition=Ready node --all --timeout=5m

# Install Istio Ambient
echo "==> Installing Istio Ambient"
istioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway' \
  --skip-confirmation

# HARD waits
kubectl wait -n istio-system --for=condition=available deployment/istiod --timeout=5m
kubectl wait -n istio-system --for=condition=Ready pod -l app=ztunnel --timeout=5m
kubectl wait -n istio-gateway --for=condition=available deployment/istio-ingressgateway --timeout=5m

kubectl wait svc istio-ingressgateway \
  -n istio-gateway \
  --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  --timeout=120s

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
helm install harbor harbor/harbor --version 1.18.1 --create-namespace \
  -n harbor \
  -f Harbor/harbor-values.yaml

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
echo "==> Waiting for CA installer to be ready on all nodes..."
kubectl rollout status daemonset/harbor-ca-installer -n kube-system --timeout=300s || {
    echo "WARNING: CA installer timed out. Checking pod status..."
    kubectl get pods -n kube-system -l name=harbor-ca-installer
    kubectl describe pods -n kube-system -l name=harbor-ca-installer
    echo "Continuing with setup despite CA installer timeout..."
}

kubectl apply -f Harbor/harbor-httproute.yaml

# Restart containerd on all nodes to pick up new CA certificates
echo "==> Restarting containerd on all nodes to trust Harbor CA"
docker exec test-cluster-1-control-plane systemctl restart containerd || echo "WARNING: Failed to restart containerd on control-plane"
docker exec test-cluster-1-worker systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker"
docker exec test-cluster-1-worker2 systemctl restart containerd || echo "WARNING: Failed to restart containerd on worker2"
echo "==> Containerd restarted on all nodes"

# Add harbor.local to /etc/hosts on all Kind nodes so containerd can resolve it
echo "==> Adding harbor.local to Kind nodes /etc/hosts"
GATEWAY_LB_IP=$(kubectl get svc istio-gateway-istio -n istio-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for node in test-cluster-1-control-plane test-cluster-1-worker test-cluster-1-worker2; do
  docker exec "$node" bash -c "grep -q 'harbor.local' /etc/hosts || echo '${GATEWAY_LB_IP} harbor.local' >> /etc/hosts"
done
echo "==> harbor.local added to Kind nodes"

sleep 15
# Create demo-apps namespace and Harbor registry secret
echo "==> Setting up demo-apps namespace and Harbor credentials"
kubectl create namespace demo-apps --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry harbor-regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n demo-apps \
  --dry-run=client -o yaml | kubectl apply -f -


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
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-builds \
  --dry-run=client -o yaml | kubectl apply -f -

sleep 1
# Apply Tekton Pipeline resources
echo "==> Deploying Tekton ServiceAccounts, Pipeline, and Tasks"
kubectl apply -f Tekton-Pipelines/configs/
kubectl apply -f Tekton-Pipelines/tekton-pipeline.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-1-clone-repo.yaml
kubectl apply -f Tekton-Pipelines/tekton-task-2-build-push.yaml
sleep 30

echo "==> Waiting for Tekton controllers to stabilize"
kubectl wait --for=condition=available deployment/tekton-pipelines-controller -n tekton-pipelines
kubectl wait --for=condition=available deployment/tekton-pipelines-webhook -n tekton-pipelines
sleep 20

echo "==> Running initial Tekton pipeline to build demo app image"
kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml

echo "==> Waiting for pipeline to complete..."
kubectl wait --for=condition=Succeeded --timeout=300s pipelinerun/clone-build-push-run -n tekton-builds || {
    echo "WARNING: Pipeline did not complete successfully. Check with:"
    echo "kubectl get pipelineruns -n tekton-builds"
    echo "kubectl logs -f pipelinerun/clone-build-push-run -n tekton-builds"
}
sleep 1

echo "================================================"
echo "* Setup ArgoCD URL: https://argocd.local"
echo "================================================"
# Add entries to /etc/hosts
grep -q "argocd.local" /etc/hosts || echo "172.20.255.201 argocd.local" | sudo tee -a /etc/hosts
grep -q "demo-app1.local" /etc/hosts || echo "172.20.255.201 demo-app1.local" | sudo tee -a /etc/hosts
# 1. Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 3. Apply custom configurations via Kustomize
kubectl apply -k ArgoCD/
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
echo "* Deploying ArgoCD Applications"
echo "================================================"

# Deploy ArgoCD Project and ApplicationSet
kubectl apply -f ArgoCD-demo-apps/projects/application-sets-projects.yaml
kubectl apply -f ArgoCD-demo-apps/applicationsets/application-sets.yaml
kubectl apply -k ArgoCD-demo-apps/apps/

echo "==> Waiting for ArgoCD Applications to be created..."
sleep 10

# Show ArgoCD Applications status
kubectl get applications -n argocd

echo "================================================"
echo "* Setup Complete! Access your applications:"
echo "* ArgoCD: https://argocd.local"
echo "* Harbor: https://harbor.local"
echo "* Tekton: https://tekton.local"
echo "* Demo App: https://demo-app1.local"
echo "================================================"
echo "* To run a Tekton pipeline:"
echo "kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml"
echo "================================================"