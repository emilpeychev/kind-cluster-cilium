# MetalLB Load Balancer Quick Start

## Overview
MetalLB provides LoadBalancer services in bare-metal Kubernetes clusters using L2/BGP protocols.

## Architecture
```mermaid
graph TB
    subgraph "KIND Cluster"
        SVC[LoadBalancer Service<br/>harbor.local]
        POD[Harbor Pods]
        SVC --> POD
    end
    
    subgraph "MetalLB Components"
        CTRL[MetalLB Controller<br/>IP Assignment]
        SPKR[MetalLB Speaker<br/>DaemonSet L2 ARP]
    end
    
    subgraph "Network"
        EXT[External Client<br/>172.20.255.201]
        NET[Docker Network<br/>172.20.0.0/16]
    end
    
    EXT --> NET
    NET --> SPKR
    SPKR --> SVC
    CTRL --> SVC
```

## Installation
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl apply -f metalLB/metallb-config.yaml
```

## Configuration
IP Pool: `172.20.255.200-172.20.255.250`

## Verification
```bash
kubectl get svc -n istio-gateway
kubectl get ipaddresspools -n metallb-system
```