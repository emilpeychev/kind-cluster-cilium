# kind-cluster-setups

## Setup

***Creation***

```sh
kind create cluster --name cluster-name
```

***Deletion***

```sh
kind delete cluster --name cluster-name 
```

***Customize your cluster***

[check page to create a config file kind-config.yaml](https://kind.sigs.k8s.io/docs/user/configuration/#a-note-on-cli-parameters-and-configuration-files)

## Select CNI plugin

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### Cilium

```sh
cilium install \
  --version 1.18.4 \
  --set kubeProxyReplacement=true \
  --set kubeProxyReplacementMode=strict \
  --set cni.exclusive=false \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.244.0.0/16 \
  --set k8s.requireIPv4PodCIDR=true

```

- Cilium go to Cilium dir
- Canal [follow the instructions on the webpage](https://docs.tigera.io/calico/latest/getting-started/kubernetes/flannel/install-for-flannel)



## Deploy dashboard

What you should do (step-by-step)

### Install METAL_LB

```sh
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Create a new IPAddressPool in the correct subnet:
# Use an IP range from 172.20.0.0/16 that is not used by your nodes (e.g., 172.20.255.200-172.20.255.250):

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.20.255.200-172.20.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv
  namespace: metallb-system
EOF
```

### Test

```sh
kubectl run -it --rm --image=busybox:1.28 testbox -- /bin/sh
# Inside the pod:
wget -O- http://foo-service:5678
wget -O- http://bar-service:8765

curl -v http://<foo-service-EXTERNAL-IP>:5678
curl -v http://<bar-service-EXTERNAL-IP>:8765
```

## Select Service mesh

```sh
kubectl create namespace istio-gateway
kubectl label namespace istio-gateway istio.io/dataplane-mode=ambient


stioctl install \
  --set profile=ambient \
  --set 'components.ingressGateways[0].name=istio-ingressgateway' \
  --set 'components.ingressGateways[0].enabled=true' \
  --set 'components.ingressGateways[0].namespace=istio-gateway' \
  --skip-confirmation
```

- Istio [Install istioctl](https://istio.io/latest/docs/ambient/getting-started/#download-the-istio-cli)
- Istio [Install Istio over the Canal cni](https://medium.com/@SabujJanaCodes/touring-the-kubernetes-istio-ambient-mesh-part-1-setup-ztunnel-c80336fcfb2d)


## Deploy httpbin (demo app)

```sh
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: istio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
      - name: httpbin
        image: postmanlabs/httpbin
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: istio
spec:
  selector:
    app: httpbin
  ports:
  - port: 80
    targetPort: 80
```

## Create TLS cert + secret

```sh
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -subj "/CN=istio-gateway-istio.istio-gateway" \
  -keyout key.pem \
  -out cert.pem
# 
kubectl create secret tls istio-gateway-credentials \
  --cert=cert.pem \
  --key=key.pem \
  -n istio-gateway
```

## Gateway API (Gateway + HTTPRoute)

```sh

# Gateway
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: istio-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
  - name: https
    protocol: HTTPS
    port: 443
    hostname: istio-gateway-istio.istio-gateway
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: istio-gateway-credentials
# HTTPRoute

---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin
  namespace: istio
spec:
  hostnames:
  - istio-gateway-istio.istio-gateway
  parentRefs:
  - name: istio-gateway
    namespace: istio-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: httpbin
      port: 80

# Apply
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml

```

## Verify services

```sh
kubectl get svc -n istio-gateway
```

## Test

```sh
# Test from inside cluster
kubectl run -it --rm testbox \
  --image=busybox:1.28 -- sh -lc \
  'wget -O- http://istio-gateway-istio.istio-gateway.svc.cluster.local/html'

# Test form host
curl -vk \
  --resolve istio-gateway-istio.istio-gateway:443:172.20.255.203 \
  https://istio-gateway-istio.istio-gateway/html

# Browser (HTTP)
http://172.20.255.203/html

# Browser (HTTPS)
https://172.20.255.203/html

(Expect cert warning — self-signed)

```

