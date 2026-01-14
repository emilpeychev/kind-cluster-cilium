# ArgoCD Image Updater Installation
# Using the legacy annotation-based version (v0.15.x)

## Install

```bash
# Install ArgoCD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v0.15.1/manifests/install.yaml

# Apply Harbor registry configuration
kubectl apply -f ArgoCD-Image-Updater/

# Restart to pick up config
kubectl rollout restart deployment argocd-image-updater -n argocd
```

## Configuration

The Image Updater uses annotations on ArgoCD Applications to configure image updates.

### Required Annotations on ArgoCD Application

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: demo=harbor.local/library/demo-app
    argocd-image-updater.argoproj.io/demo.update-strategy: newest-build
    argocd-image-updater.argoproj.io/demo.pull-secret: pullsecret:argocd/harbor-registry-creds
```

## Verify

```bash
# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f

# Check deployment
kubectl get deployment argocd-image-updater -n argocd
```
