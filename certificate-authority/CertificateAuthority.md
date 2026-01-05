# Creating a Local Certificate Authority for TLS in Development

When working with TLS in development, self-signed certificates often lead to annoying browser and CLI prompts.

```sh
Step 1 — Create a local Certificate Authority (CA)

This CA is only for your machine.

1.1 Generate CA private key
openssl genrsa -out tls/ca.key 4096


```

***This is the root of trust***

- Keep it private

- Never commit it

## 1.2 Create CA certificate

```sh
openssl req -x509 -new -nodes \
  -key tls/ca.key \
  -sha256 -days 365 \
  -out tls/ca.crt \
  -subj "/CN=Local Dev CA"
```

***You now have:***

```sh
ca.key → CA private key

ca.crt → CA public certificate (this is what we trust)

```

## Step 2 — Create a certificate request for the Gateway

***We already have the SAN config — good.***

***2.1 Generate gateway key + CSR***

```sh
openssl req -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout tls/key.pem \
  -out tls/gateway.csr \
  -config tls/openssl-local.cnf
```

***This creates:***

```yaml
key.pem → gateway private key

gateway.csr → “please sign me” request
```

## Step 3 — Sign the gateway cert with your CA

***This is the magic step.***

```sh
openssl x509 -req \
  -in tls/gateway.csr \
  -CA tls/ca.crt \
  -CAkey tls/ca.key \
  -CAcreateserial \
  -out tls/cert.pem \
  -days 365 \
  -sha256 \
  -extensions req_ext \
  -extfile tls/openssl-local.cnf
```

***Results:***

```yaml
cert.pem → gateway certificate signed by your CA

cert.pem is NOT self-signed

It is signed by your CA

SANs still apply (*.local, localhost)
```

## Step 4 — Verify (always verify)

```sh
openssl x509 -in tls/cert.pem -noout -text | grep -A2 "Subject Alternative Name"
```

***You should see:***

  ```yaml
DNS:*.local, DNS:localhost
```

***And verify the chain:***

```sh
openssl verify -CAfile tls/ca.crt tls/cert.pem
```

***Expected:***

tls/cert.pem: OK

## Step 5 — Trust the CA on your machine

This is what removes the prompt.

***On Linux (most distros)***

```sh
# This will copy the CA cert to the trusted store
sudo cp tls/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt
# Update the trusted certificates
sudo update-ca-certificates
```

***On macOS***

```sh
sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  tls/ca.crt
```

***After this:***

```yaml
Your OS trusts anything signed by your CA

Browsers, curl, argocd CLI all inherit this
```

## Step 6 — Deploy cert to Istio Gateway

## Create or update the TLS secret

```sh

kubectl create secret tls istio-gateway-credentials \
  --cert=tls/cert.pem \
  --key=tls/key.pem \
  -n istio-gateway \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/istio-ingressgateway -n istio-gateway
```

## Step 7 — Test (this is the payoff)

```sh
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

argocd login argocd.local \
  --username admin \
  --password "$PASSWORD" \
  --grpc-web
```

***Expected:***
✔️ No prompt
✔️ No --insecure
✔️ Full TLS validation

Mental model (lock this in)
Self-signed cert
  → only YOU say “trust me”

CA-signed cert
  → a trusted authority vouches for it

You just became your own authority.

What this gives you (why this is worth it)

Same trust model as production

Same failure modes as production

No bad habits

No emotional whiplash from TLS prompts

Deep understanding of how TLS really works

One honest note (important)

This is not beginner material.

If this felt heavy — that’s normal.
You’re now touching PKI, which is famously hard.

You’re doing it correctly.

Next (only if you want)

We can:

Fold this into your script cleanly

Make it idempotent

Or later replace it with cert-manager

But pause for a second — what you just explored is real infrastructure knowledge.

Take that in 👍
