# Tekton CI/CD Pipeline Quick Start

## Overview
Tekton provides Kubernetes-native CI/CD pipeline capabilities with reusable tasks and pipeline definitions. This setup demonstrates continuous integration and deployment workflows.

## Architecture
```mermaid
graph TB
    subgraph "Tekton Components"
        TR[TaskRun] --> T[Task]
        PR[PipelineRun] --> P[Pipeline]
        P --> T1[Clone Repository Task]
        P --> T2[Build & Push Task]
    end
    
    subgraph "Git Integration"
        GR[GitHub Repository] --> T1
    end
    
    subgraph "Container Registry"
        T2 --> HR[Harbor Registry]
    end
    
    subgraph "ArgoCD Sync"
        HR --> AC[ArgoCD]
        AC --> KD[K8s Deployment]
    end
```

## Pipeline Workflow
```mermaid
sequenceDiagram
    participant User
    participant Pipeline
    participant Git
    participant Harbor
    participant ArgoCD
    participant K8s
    
    User->>Pipeline: Trigger PipelineRun
    Pipeline->>Git: Clone repository (master branch)
    Pipeline->>Harbor: Build & push image
    Harbor->>ArgoCD: Image available
    ArgoCD->>K8s: Deploy application
    K8s->>User: Application accessible
```

## Quick Start

### 1. Deploy Pipeline Components
```bash
kubectl apply -f Tekton-Pipelines/
```

### 2. Trigger Pipeline
```bash
kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml
```

### 3. Monitor Pipeline
```bash
kubectl get pipelineruns -n tekton-builds
kubectl logs -f pipelinerun/demo-app-pipeline-run -n tekton-builds
```

## Pipeline Components
- **Clone Task**: Fetches source code from GitHub repository
- **Build Task**: Builds Docker image and pushes to Harbor registry
- **ServiceAccount**: Provides required permissions for pipeline execution

## Integration Points
- **Git Repository**: Source code location (master branch)
- **Harbor Registry**: Container image storage at `harbor.local`
- **ArgoCD**: Automated deployment synchronization
- **Istio Gateway**: HTTPS access at `https://demo-app1.local`
