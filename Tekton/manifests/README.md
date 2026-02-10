# Tekton Manifests

This directory contains the Tekton installation manifests that are deployed via ArgoCD.

## Files

### tekton-pipelines.yaml

- **Source**: <https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml>
- **Description**: Core Tekton Pipelines CRDs, controllers, and webhooks
- **Modifications**: `set-security-context: "true"` in feature-flags ConfigMap (allows TaskRuns in restricted namespaces)
- **Components**:
  - Custom Resource Definitions (CRDs) for Pipelines, Tasks, Runs
  - tekton-pipelines-controller deployment
  - tekton-pipelines-webhook deployment
  - RBAC resources
  - ConfigMaps and Services

### tekton-dashboard.yaml

- **Source**: <https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml>
- **Description**: Tekton Dashboard web UI
- **Access**: <https://tekton.local> (via HTTPRoute)

### kustomization.yaml

- **Description**: Kustomize configuration for managing the manifests
- **Purpose**: Allows ArgoCD to apply all resources together

## Deployment

These manifests are deployed via ArgoCD:

- **Application**: `Tekton/application.yaml`
- **Project**: `Tekton/project.yaml`
- **Namespaces**:
  - `tekton-pipelines` - Control plane (privileged)
  - `tekton-builds` - Pipeline execution environment (baseline PSA)

## Updating Manifests

To update to a newer version of Tekton:

```bash
# Update Tekton Pipelines
curl -sL https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml \
  -o Tekton/manifests/tekton-pipelines.yaml

# Enable security context support (required for baseline PSA)
sed -i 's/set-security-context: "false"/set-security-context: "true"/' \
  Tekton/manifests/tekton-pipelines.yaml

# Update Tekton Dashboard
curl -sL https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml \
  -o Tekton/manifests/tekton-dashboard.yaml

# Commit and push - ArgoCD will auto-sync
git add Tekton/manifests/
git commit -m "Update Tekton to latest version"
git push
```

## Architecture

```html
tekton-pipelines (namespace)
├── tekton-pipelines-controller (deployment)
├── tekton-pipelines-webhook (deployment)
├── tekton-dashboard (deployment)
└── CRDs (Pipeline, Task, PipelineRun, TaskRun, etc.)

tekton-builds (namespace)
├── Pipeline definitions
├── Task definitions
├── ServiceAccounts (restricted)
└── Secrets (Harbor, GitHub)
```
