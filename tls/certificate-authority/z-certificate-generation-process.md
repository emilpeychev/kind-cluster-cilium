graph TB
    subgraph "Certificate Creation"
        C1[OpenSSL Config
SAN Extensions]
        C2[Generate Private Key
RSA 2048-bit]
        C3[Create Certificate
X.509 Self-signed]
        C4[Verify SANs
Domain Validation]
    end
    
    subgraph "Kubernetes Deployment"
        K1[Create TLS Secret]
        K2[Apply to Gateway]
        K3[Gateway Uses Cert
HTTPS Termination]
    end
    
    C1 --> C2
    C2 --> C3
    C3 --> C4
    C4 --> K1
    K1 --> K2
    K2 --> K3