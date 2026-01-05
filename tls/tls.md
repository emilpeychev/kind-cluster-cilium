# TLS

📚 Docs

***How to create proper TLS certificates for Kubernetes***

[TSL Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

[Kubernetes Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)

```sh
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -config openssl-local.cnf \
  -extensions req_ext
```

## Verify the certificate (important habit)

```sh
openssl x509 -in cert.pem -noout -text | grep -A1 "Subject Alternative Name"
```

## Deploy secret

```sh  
kubectl create secret tls istio-gateway-credentials \
  --cert=cert.pem \
  --key=key.pem \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -
```

