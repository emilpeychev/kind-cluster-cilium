# Tekton Dynamic Image Naming Strategies

## Current Implementation
**Registry**: `harbor.local/library/demo-app`  
**Tag**: `v0.1` (semantic version)

## Recommended Strategies

### 1. **Semantic Versioning (Current)**
Best for: Production releases, stable versions

```yaml
params:
  - name: VERSION
    type: string
    default: "v0.1"
    
# Build: harbor.local/library/demo-app:v0.1
```

**Pros**: Clear version tracking, predictable, production-ready  
**Cons**: Manual version bumping required

---

### 2. **Git Commit SHA**
Best for: Development, traceability

```yaml
tasks:
  - name: build-and-push-image
    params:
      - name: IMAGE_URL
        value: $(params.IMAGE_REPO):$(tasks.clone-repo.results.commit)
```

**Pros**: Automatic, unique, traceable to source code  
**Cons**: Not human-readable, harder to track versions

---

### 3. **Hybrid: Version + SHA**
Best for: Production + traceability

```yaml
# Build two tags:
# 1. harbor.local/library/demo-app:v0.1
# 2. harbor.local/library/demo-app:v0.1-abc1234

params:
  - name: IMAGE_URL
    value: $(params.IMAGE_REPO):$(params.VERSION)
  - name: IMAGE_URL_LATEST
    value: $(params.IMAGE_REPO):$(params.VERSION)-$(tasks.clone-repo.results.commit)
```

**Pros**: Version clarity + commit traceability  
**Cons**: Creates two tags per build

---

### 4. **Timestamp-based**
Best for: Development iterations

```yaml
# Example: v0.1-20260114-160325
# Format: VERSION-YYYYMMDD-HHMMSS

steps:
  - name: generate-timestamp
    image: busybox
    script: |
      date +%Y%m%d-%H%M%S > /workspace/timestamp.txt
```

**Pros**: Chronological ordering, human-readable  
**Cons**: Not tied to git history

---

### 5. **Branch + Build Number**
Best for: CI/CD with build servers

```yaml
# Example: master-123, feature-branch-45

params:
  - name: GIT_BRANCH
  - name: BUILD_NUMBER
    
# Tag: harbor.local/library/demo-app:master-123
```

**Pros**: Branch awareness, build tracking  
**Cons**: Requires external build counter

---

## ArgoCD Image Updater Integration

### Option A: Semantic Version Pattern
```yaml
# ApplicationSet annotation
argocd-image-updater.argoproj.io/image-list: demo=harbor.local/library/demo-app:~v0
argocd-image-updater.argoproj.io/demo.update-strategy: semver
```

### Option B: Latest Tag Pattern
```yaml
argocd-image-updater.argoproj.io/image-list: demo=harbor.local/library/demo-app:~v0.1
argocd-image-updater.argoproj.io/demo.update-strategy: newest-build
```

### Option C: Git SHA via Write-back
```yaml
# Image Updater writes new SHA to kustomization.yaml
argocd-image-updater.argoproj.io/write-back-method: git
argocd-image-updater.argoproj.io/git-branch: image-updates
```

---

## Recommended Setup for This Project

### Current Pipeline Enhancement
```yaml
params:
  - name: VERSION
    type: string
    default: "v0.1"
    description: "Semantic version (e.g., v0.1, v0.2, v1.0)"

tasks:
  - name: build-and-push-image
    params:
      # Primary tag: v0.1
      - name: IMAGE_URL
        value: $(params.IMAGE_REPO):$(params.VERSION)
      # Secondary tag: latest (for easy dev access)
      - name: IMAGE_URL_LATEST
        value: $(params.IMAGE_REPO):latest
```

### Future: Add Commit SHA Tracking
```yaml
# Add to pipeline for full traceability
- name: IMAGE_URL_SHA
  value: $(params.IMAGE_REPO):$(params.VERSION)-$(tasks.clone-repo.results.commit)
```

---

## Quick Reference

| Strategy | Tag Format | Use Case | Auto-Update |
|----------|------------|----------|-------------|
| Semantic | `v0.1` | Production | Manual |
| Git SHA | `abc1234` | Development | Auto |
| Hybrid | `v0.1-abc1234` | Both | Semi-auto |
| Timestamp | `v0.1-20260114` | Dev iterations | Auto |
| Latest | `latest` | Quick testing | Auto |

---

## Current Fix Applied

Removed `newName: library/demo-app` from kustomization.yaml to preserve full registry path `harbor.local/library/demo-app:v0.1`.
