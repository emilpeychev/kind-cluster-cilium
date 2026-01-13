#!/usr/bin/env bash
set -euo pipefail
# Part 4 - Config: ArgoCD Configuration and Automation
# This script configures ArgoCD and deploys applications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "================================================"
echo "* Configuring ArgoCD: https://argocd.local"
echo "================================================"

# Add entries to /etc/hosts
grep -q "argocd.local" /etc/hosts || echo "172.20.255.201 argocd.local" | sudo tee -a /etc/hosts
grep -q "demo-app1.local" /etc/hosts || echo "172.20.255.201 demo-app1.local" | sudo tee -a /etc/hosts

# 3. Apply custom configurations via Kustomize
kubectl apply -k "${REPO_ROOT}/ArgoCD/"
sleep 1
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd
sleep 10

# 4. Get admin password
echo "==> ArgoCD Admin Password:"
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
kubectl apply -f "${REPO_ROOT}/ArgoCD-demo-apps/projects/application-sets-projects.yaml"
kubectl apply -f "${REPO_ROOT}/ArgoCD-demo-apps/applicationsets/application-sets.yaml"
kubectl apply -k "${REPO_ROOT}/ArgoCD-demo-apps/apps/"

echo "==> Waiting for ArgoCD Applications to be created..."
sleep 10

# Show ArgoCD Applications status
kubectl get applications -n argocd

echo "================================================"
echo "✔ Part 4 Config complete - ArgoCD configured"
echo "================================================"
echo
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
