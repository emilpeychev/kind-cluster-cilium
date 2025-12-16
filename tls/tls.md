# TLS

```sh
openssl genrsa -out key.pem 2048

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -subj "/CN=istio-gateway-istio.istio-gateway" \
  -addext "subjectAltName=DNS:istio-gateway-istio.istio-gateway,DNS:localhost"


```

## Deploy secret

```sh  
kubectl create secret tls istio-gateway-credentials \
  --cert=cert.pem \
  --key=key.pem \
  -n istio-gateway

```
