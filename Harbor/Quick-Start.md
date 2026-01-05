# Harbor Quick start

- Use helm

```sh
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor --version 1.18.1 \
  --create-namespace \
  -n harbor \
  -f harbor-values.yaml
```

# Configure ambient namespace

```sh
kubectl label namespace harbor istio.io/dataplane-mode=ambient --overwrite
kubectl get namespace harbor --show-labels

```

# Remove Harbor helm chart and pvcs

```sh
helm uninstall harbor -n harbor
kubectl delete pvc -n harbor --all

kubectl patch pvc data-harbor-trivy-0 -n harbor \
  -p '{"metadata":{"finalizers":null}}'

kubectl patch pvc database-data harbor-database-0 -n harbor \
  -p '{"metadata":{"finalizers":null}}'

kubectl patch pvc harbor-jobservice -n harbor \
  -p '{"metadata":{"finalizers":null}}'

kubectl patch pvc harbor-registry -n harbor \
  -p '{"metadata":{"finalizers":null}}'

kubectl get pvc -n harbor
```

## Harbor hTTPRoute architecture

- Mapping of paths to Harbor services is core to proper routing.
- Below is the exact HTTPRoute pattern.
- `NOTHING ELSE is WORKING` except this.

```yaml
Routing model (from Harbor Helm chart)

/api/, /service/, /v2/, /c/ → harbor-core
```

```sh
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: harbor
  namespace: harbor
spec:
  parentRefs:
  - name: istio-gateway
    namespace: istio-gateway
    sectionName: https

  hostnames:
  - harbor.local

  rules:
  # API / registry / controller → core
  - matches:
    - path:
        type: PathPrefix
        value: /api/
    - path:
        type: PathPrefix
        value: /service/
    - path:
        type: PathPrefix
        value: /v2/
    - path:
        type: PathPrefix
        value: /c/
    backendRefs:
    - name: harbor-core
      port: 80

  # UI → portal
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: harbor-portal
      port: 80
    ```
