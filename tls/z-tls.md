# TLS Certificate Configuration

## Overview
TLS certificate setup for Kubernetes gateways using OpenSSL with proper Subject Alternative Names (SANs) for local development domains.

## Certificate Generation Process
```mermaid
graph TB
    subgraph "Certificate Creation"
        C1[OpenSSL Config<br/>SAN Extensions]
        C2[Generate Private Key<br/>RSA 2048-bit]
        C3[Create Certificate<br/>X.509 Self-signed]
        C4[Verify SANs<br/>Domain Validation]
    end
    
    subgraph "Kubernetes Deployment"
        K1[Create TLS Secret]
        K2[Apply to Gateway]
        K3[Gateway Uses Cert<br/>HTTPS Termination]
    end
    
    C1 --> C2
    C2 --> C3
    C3 --> C4
    C4 --> K1
    K1 --> K2
    K2 --> K3
```

## Certificate Generation

### Create Certificate with SANs
```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -config openssl-local.cnf \
  -extensions req_ext
```

### Verify Certificate SANs
```bash
openssl x509 -in cert.pem -noout -text | grep -A1 "Subject Alternative Name"
```

**Expected Output:**
```
X509v3 Subject Alternative Name:
    DNS:*.local, DNS:localhost
```

## Kubernetes Deployment

### Create TLS Secret
```bash
kubectl create secret tls istio-gateway-credentials \
  --cert=cert.pem \
  --key=key.pem \
  -n istio-gateway
```

### Verify Secret
```bash
kubectl get secret istio-gateway-credentials -n istio-gateway -o yaml
```

## OpenSSL Configuration
File: `openssl-local.cnf`
```ini
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext

[req_distinguished_name]

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.local
DNS.2 = localhost
```

## Current Setup
- **Certificate Type**: X.509 self-signed
- **Key Algorithm**: RSA 2048-bit
- **Validity**: 365 days
- **Domains**: `*.local`, `localhost`
- **Usage**: Istio Gateway TLS termination

## References
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
- [Istio Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
  --key=key.pem \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -
```

