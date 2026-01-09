Gateway API + Istio Ambient — Test Summary
1️⃣ MetalLB / External IP reachability
Test
curl -v http://172.20.255.201

Result
HTTP/1.1 404
server: istio-envoy

What this proved

MetalLB is advertising the IP

LoadBalancer Service is reachable

Envoy is answering traffic

404 is expected (no hostname match yet)

2️⃣ Gateway listener is active (HTTP)
Test
curl -v http://172.20.255.201 \
  -H "Host: istio-gateway-istio.istio-gateway"

Result
HTTP/1.1 404
server: istio-envoy

What this proved

Gateway HTTP listener is working

Hostname routing is enforced

Traffic reaches Envoy correctly

3️⃣ TLS termination works (HTTPS)
Test
curl -vk \
  --resolve istio-gateway-istio.istio-gateway:443:172.20.255.201 \
  https://istio-gateway-istio.istio-gateway/

Result
TLS handshake succeeded
server: istio-envoy

What this proved

HTTPS listener is active

TLS certificate is loaded

TLS is terminated at the Gateway

HTTP/2 is negotiated

4️⃣ HTTPRoute attachment validation
Test
kubectl describe httproute httpbin -n default

Result
Accepted: True
ResolvedRefs: True

What this proved

HTTPRoute is valid

Cross-namespace routing is allowed

Gateway accepted the route

References to Service are correct

5️⃣ Backend health (inside cluster)
Test
kubectl get pods -l app=httpbin
kubectl get endpoints httpbin

Result
Pod: Running
Endpoints: <pod-ip>:80

What this proved

Application pod is healthy

Service has active endpoints

Traffic can be forwarded upstream

6️⃣ End-to-end HTTPS routing
Test

```sh
curl -vk \
  --resolve istio-gateway-istio.istio-gateway:443:172.20.255.201 \
  https://istio-gateway-istio.istio-gateway/get
```

Result
HTTP/2 200
application/json

What this proved

Gateway → HTTPRoute → Service → Pod works

TLS → HTTP handoff is correct

L7 routing is functional

Envoy successfully proxies traffic