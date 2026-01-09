# KIND Cluster Configuration

## Overview
KIND (Kubernetes IN Docker) provides local Kubernetes clusters using Docker containers as nodes.

## Architecture
```mermaid
graph TB
    subgraph "Docker Host"
        subgraph "KIND Cluster"
            CP[Control Plane<br/>test-cluster-1-control-plane]
            W1[Worker 1<br/>test-cluster-1-worker]
            W2[Worker 2<br/>test-cluster-1-worker2]
        end
        
        subgraph "Docker Network"
            NET[kind network<br/>172.20.0.0/16]
        end
        
        CP --> NET
        W1 --> NET
        W2 --> NET
    end
    
    subgraph "Port Mapping"
        HTTP[80:30080]
        HTTPS[443:30443]
    end
    
    NET --> HTTP
    NET --> HTTPS
```

## Configuration
- **Cluster Name**: test-cluster-1  
- **Node Count**: 3 (1 control-plane, 2 workers)
- **Network**: 172.20.0.0/16
- **Port Mapping**: 80/443 for ingress

## Creation
```bash
kind create cluster --config=kind-config.yaml
```

## Management  
```bash
kubectl get nodes
kind get clusters
kind delete cluster --name test-cluster-1
```