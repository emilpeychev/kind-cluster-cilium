
# <Local ArgoCD Quick Start Guide>

---
[![Yettel](https://img.shields.io/badge/POC-Yettel-B4FF00?style=flat-rounded&logo=cloud&logoColor=purple)](https://www.yettel.bg/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-FE7338?style=flat-rounded&logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)

---

## 1. Install ArgoCD via Helm

```sh
kubectl create namespace argocd
kubectl apply -n argocd -f <https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.0/manifests/install.yaml>

## 2. Wait for ArgoCD to be ready

kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

## 3. Get admin password

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

## 4. Access ArgoCD UI (in separate terminal)

kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# UI: <https://localhost:8080> (admin / password from step 3)

## 5. (Optional) Quick ArgoCD login helper script (CLI)

cat > /tmp/argocd-login.sh <<'EOF'

# !/usr/bin/env bash

set -euo pipefail
NS=${ARGOCD_NAMESPACE:-argocd}
SERVER=${ARGO_SERVER:-localhost:8080}

if ! pgrep -f "kubectl port-forward .*svc/argocd-server .*8080:443" >/dev/null; then
  kubectl port-forward svc/argocd-server -n "$NS" 8080:443 >/tmp/argocd-port-forward.log 2>&1 &
  sleep 3
fi

PASSWORD=$(kubectl -n "$NS" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login "$SERVER" --username admin --password "$PASSWORD" --insecure
EOF
chmod +x /tmp/argocd-login.sh
/tmp/argocd-login.sh

## 6. Add repositories for Git and Helm charts

argocd repo add <git@github.com>:emilpeychev/kind-cluster-cilium.git --ssh-private-key-path ~/.ssh/id_ed25519

kubectl apply -f argocd/projects/
kubectl apply -f argocd/applicationsets/

## 7. Deploy GitOps projects and applications

argocd repo add <https://nicklasfrahm.github.io/helm-charts> \
  --type helm \
  --name gateway-api-helm

argocd repo add <https://helm.nginx.com/stable> \
  --type helm \
  --project kubernetes-infrastructure \
  --name nginx-helm

argocd repo add <https://charts.jetstack.io> \
  --type helm \
  --project kubernetes-infrastructure \
  --name cert-manager-helm

argocd repo add <https://prometheus-community.github.io/helm-charts> \
  --type helm \
  --project kubernetes-infrastructure \
  --name prometheus-community
