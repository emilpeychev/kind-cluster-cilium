# ArgoCD Image Updater Quick Start

ArgoCD Image Updater automatically updates container images in Kubernetes workloads managed by ArgoCD.

## Prerequisites

- ArgoCD installed and running
- Harbor registry accessible at `harbor.local`

## Installation

### 1. Install Image Updater

```bash
kubectl apply -f ArgoCD-Image-Updater/image-updater-install.yaml
```

### 2. Create Harbor credentials secret

```bash
kubectl apply -f ArgoCD-Image-Updater/image-updater-config.yaml
```

### 3. Verify Installation

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

## Application Configuration

Add these annotations to your ArgoCD Application to enable automatic image updates:

```yaml
metadata:
  annotations:
    # List of images to track (alias=image:constraint)
    argocd-image-updater.argoproj.io/image-list: demo-app=harbor.local/library/demo-app
    
    # Update strategy: newest-build, semver, latest, digest
    argocd-image-updater.argoproj.io/demo-app.update-strategy: newest-build
    
    # Write-back method: argocd or git
    argocd-image-updater.argoproj.io/write-back-method: argocd
```

## Update Strategies

| Strategy | Description |
|----------|-------------|
| `semver` | Update to the latest semantic version tag |
| `latest` | Update to the most recently created image tag |
| `newest-build` | Update to the image with the most recent build timestamp |
| `digest` | Update to the newest digest (for static tags like `latest`) |

## Testing

### Check Image Updater Logs

```bash
kubectl logs -n argocd deployment/argocd-image-updater -f
```

### Force Image Check

```bash
kubectl rollout restart deployment/argocd-image-updater -n argocd
```

### Verify Application Annotations

```bash
kubectl get application demo-apps -n argocd -o jsonpath='{.metadata.annotations}' | jq
```

## Integration Flow

1. **Tekton Pipeline** builds and pushes new image to Harbor
2. **Image Updater** polls Harbor registry for new images (every 2 minutes by default)
3. **Image Updater** detects new image and updates ArgoCD Application
4. **ArgoCD** syncs the application with the new image tag
5. **Kubernetes** pulls the new image and updates the deployment

## Files

- [image-updater-install.yaml](image-updater-install.yaml) - Core installation manifests (ServiceAccount, RBAC, Deployment, ConfigMaps)
- [image-updater-config.yaml](image-updater-config.yaml) - Harbor registry configuration and credentials

## Troubleshooting

### Check if Image Updater can access Harbor

```bash
kubectl exec -n argocd deployment/argocd-image-updater -- \
  argocd-image-updater test harbor.local/library/demo-app
```

### View current image update status

```bash
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,IMAGE:.status.summary.images'
```

### Enable debug logging

Edit the ConfigMap:
```bash
kubectl edit configmap argocd-image-updater-config -n argocd
```

Change `log.level` from `info` to `debug`.
