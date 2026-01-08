# Istio Ambient Mesh Architecture

## Overview
Istio Ambient Mesh provides service mesh capabilities without sidecar proxies, using node-level dataplane components for simplified operations and reduced resource overhead.

## Architecture Components
```mermaid
graph TB
    subgraph "Kubernetes Node"
        ZT[ztunnel<br/>L4 + mTLS + Identity]
        WP[Waypoint Proxy<br/>L7 Processing]
    end
    
    subgraph "istio-gateway Namespace"
        IG[Istio Gateway]
        IG --> ZT
    end
    
    subgraph "Application Namespaces"
        NS1[demo-apps<br/>ambient enabled]
        NS2[tekton-builds<br/>ambient enabled]
        NS1 --> WP
        NS2 --> WP
    end
    
    ZT --> WP
    WP --> IG
```

## Traffic Flow
```mermaid
sequenceDiagram
    participant Client
    participant Gateway
    participant ztunnel
    participant Waypoint
    participant App
    
    Client->>Gateway: HTTPS Request
    Gateway->>ztunnel: L4 Interception
    ztunnel->>Waypoint: L7 Processing
    Waypoint->>App: Authorized Request
    App->>Waypoint: Response
    Waypoint->>ztunnel: L4 Response
    ztunnel->>Gateway: mTLS Response
    Gateway->>Client: HTTPS Response
```

## Gateway API Flow
```mermaid
graph LR
    Client[Browser] --> MetalLB[MetalLB External IP]
    MetalLB --> Gateway[Istio Gateway<br/>TLS Termination]
    Gateway --> HTTPRoute[HTTPRoute<br/>Path Matching]
    HTTPRoute --> Service[K8s Service]
    Service --> Pod[Application Pod]
```

## Namespace Configuration

### Gateway Namespace
```bash
kubectl create namespace istio-gateway
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient
```

### Application Namespaces
```bash
kubectl label namespace demo-apps istio.io/dataplane-mode=ambient
kubectl label namespace tekton-builds istio.io/dataplane-mode=ambient
```

## Key Benefits
- **No Sidecars**: Reduced resource overhead and operational complexity
- **Automatic mTLS**: Zero-trust networking without configuration
- **Selective Enablement**: Per-namespace opt-in model
- **Gateway API**: Modern ingress with Kubernetes-native configuration

## Current Setup
- **Istio Version**: v1.28.2 Ambient Mode
- **Gateway**: HTTPS termination for `demo-app1.local` and `harbor.local`
- **mTLS**: Automatic between mesh-enabled namespaces
- **Observability**: Integrated with Kubernetes metrics

## Installation Command
```bash
istioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway'
```