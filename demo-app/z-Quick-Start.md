# Demo Application Quick Start

## Overview
Simple nginx-based demo application deployed via GitOps with Tekton CI/CD pipeline.

## Architecture
```mermaid
graph TB
    subgraph "CI/CD Pipeline"
        GIT[Git Repository<br/>demo-app source]
        TKN[Tekton Pipeline<br/>Build & Push]
        HRB[Harbor Registry<br/>harbor.local]
    end
    
    subgraph "GitOps Deployment"
        ARGO[ArgoCD<br/>Sync from Git]
        K8S[K8s Deployment<br/>demo-apps namespace]
    end
    
    subgraph "Traffic Routing"
        IST[Istio Gateway<br/>HTTPS Termination]
        HR[HTTPRoute<br/>demo-app1.local]
        SVC[Service<br/>ClusterIP]
    end
    
    GIT --> TKN
    TKN --> HRB
    HRB --> ARGO
    ARGO --> K8S
    IST --> HR
    HR --> SVC
    SVC --> K8S
```

## Access
- **URL**: https://demo-app1.local
- **Content**: "Hello from Tekton" HTML page

## Pipeline
```bash
kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml
kubectl get pipelineruns -n tekton-builds
```

## Components
- **Namespace**: demo-apps
- **Image**: harbor.local/library/demo-app:latest
- **Replicas**: 2
- **Resources**: 100m CPU, 128Mi memory