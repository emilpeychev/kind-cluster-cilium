# Istio Ambient: namespaces, labels, and why routing breaks without them

- What “Ambient Mesh” really means (important mental model)

- Istio Ambient does NOT inject sidecars.
- Instead, it uses node-level dataplane components:

![daemonset](https://raw.githubusercontent.com/kubernetes/community/master/icons/svg/resources/daemonset.svg) - 

- ztunnel (L4, mTLS, identity)

- Waypoint proxies (L7, optional, per-namespace / per-service)

- Traffic only enters the mesh if the namespace is explicitly opted in.

![namespace](https://raw.githubusercontent.com/kubernetes/community/master/icons/svg/resources/namespace.svg) **Why you created a dedicated gateway namespace**

```sh
kubectl create namespace istio-gateway
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient
```

```yaml

***Diagram***

What this does
Namespace: istio-gateway
└── Labeled as "ambient"
    └── Traffic to/from pods in this namespace is intercepted by ztunnel
```

***This ensures:***

- The Ingress Gateway pod participates in the ambient dataplane

***L4 traffic interception works***

- mTLS can be enforced later

***Why a dedicated namespace is best practice***

Separation of concerns:

istio-gateway → edge traffic

istio → workloads

Easier RBAC

Easier policy scoping

Matches upstream Istio examples

📚 Docs

https://istio.io/latest/docs/ambient/overview/

https://istio.io/latest/docs/ambient/install/

***Installing the Ambient profile***

```sh
istioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway'
```

***What this actually installs***

+ ztunnel (DaemonSet, every node)
+ istiod (control plane)
+ Ingress Gateway (Envoy)
- NO sidecars
- NO iptables per-pod

***Why explicit ingress gateway enablement matters***

Ambient mesh does not auto-create ingress gateways.

***If you skip this:***

+ Gateway API objects exist
+ But no data plane receives traffic
+ Result: “Gateway looks fine but nothing routes” ❌

***This is the #1 ambient trap.***

⚠ Why you should label application namespaces too



You deployed httpbin in namespace istio.

But you did not show:

kubectl label namespace istio istio.io/dataplane-mode=ambient

What happens without the label
Client → Gateway (ambient)
         ↓
      Service → Pod (NOT ambient)


This can still “work” because:

Gateway → Service traffic is plain Kubernetes networking

No mesh features apply to backend traffic

Why labeling is important anyway

Enables:

mTLS

L7 policies

AuthorizationPolicy

Makes behavior explicit

Prevents future confusion

Recommended baseline
kubectl label ns istio istio.io/dataplane-mode=ambient
kubectl label ns istio-gateway istio.io/dataplane-mode=ambient


📚 Docs

https://istio.io/latest/docs/ambient/usage/

2️⃣ TLS certs: CN-only, no SANs — why browsers warn
Your cert creation
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -subj "/CN=istio-gateway-istio.istio-gateway" \
  -keyout key.pem \
  -out cert.pem

What’s missing: SANs

Modern TLS ignores CN for hostname validation.

Browsers require:

X509v3 Subject Alternative Name:
  DNS: istio-gateway-istio.istio-gateway


Without SANs:

TLS still encrypts traffic

Identity verification fails

Browser shows ⚠️ warning

Why this is fine for a lab

Gateway terminates TLS correctly

Envoy loads the secret correctly

HTTPS works

Gateway API config is validated

You are testing plumbing, not PKI.

How to generate a “proper” lab cert (optional)
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -subj "/CN=istio-gateway-istio.istio-gateway" \
  -addext "subjectAltName=DNS:istio-gateway-istio.istio-gateway"


📚 Docs

https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets

https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/

3️⃣ Gateway API: how traffic actually flows (ASCII diagram)
High-level traffic flow
[ Client / Browser ]
        |
        | HTTPS :443
        v
[ MetalLB External IP ]
        |
        v
[ Istio Ingress Gateway (Envoy) ]
        |
        | HTTP (decrypted)
        v
[ HTTPRoute ]
        |
        v
[ Service: httpbin ]
        |
        v
[ Pod: httpbin ]

Gateway object — what each part does
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: istio-gateway
spec:
  gatewayClassName: istio

gatewayClassName: istio
GatewayClass "istio"
└── Controller: Istio
    └── Reconciles Gateway → Envoy config


Without this:

Gateway is ignored

No controller binds it

📚 https://gateway-api.sigs.k8s.io/concepts/gateway-classes/

Listeners: 80 vs 443
listeners:
- name: http
  protocol: HTTP
  port: 80
- name: https
  protocol: HTTPS
  port: 443


This creates two independent entry points.

ASCII:

:80  ──► plaintext HTTP
:443 ──► TLS → decrypt → HTTP

TLS termination
tls:
  mode: Terminate
  certificateRefs:
  - kind: Secret
    name: istio-gateway-credentials


Meaning:

Client TLS
   ↓
[ Envoy ]
   ↓  (decrypted)
HTTP routing rules


No passthrough, no backend TLS required.

📚 https://gateway-api.sigs.k8s.io/guides/tls/

HTTPRoute — how routing decisions are made
kind: HTTPRoute
metadata:
  name: httpbin
  namespace: istio

Cross-namespace routing (important)
parentRefs:
- name: istio-gateway
  namespace: istio-gateway


This explicitly says:

This route attaches to:
Gateway "istio-gateway" in namespace "istio-gateway"


Gateway API does not allow implicit cross-namespace binding.

📚 https://gateway-api.sigs.k8s.io/concepts/security-model/

Hostnames
hostnames:
- istio-gateway-istio.istio-gateway


This must match:

TLS SNI

Host header

PathPrefix routing
matches:
- path:
    type: PathPrefix
    value: /


ASCII:

/        → httpbin
/api     → httpbin
/foo/bar → httpbin


This is the simplest, safest default.

Backend reference
backendRefs:
- name: httpbin
  port: 80


This resolves to:

Service: httpbin.istio.svc.cluster.local:80

End-to-end ASCII (final)
Browser
  |
  | HTTPS + SNI
  v
MetalLB IP
  |
  v
Envoy Gateway (istio-gateway ns)
  |  TLS terminate
  |  HTTPRoute match
  v
Service httpbin (istio ns)
  |
  v
Pod httpbin

Why this is “exactly how Gateway API should be used”

✔ Clear separation:

Gateway = infra / edge

HTTPRoute = app ownership

✔ No legacy Istio CRDs

✔ Explicit cross-namespace binding

✔ TLS handled at the edge

✔ Works identically across:

Istio

Envoy Gateway

Future Gateway API implementations