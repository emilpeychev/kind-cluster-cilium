# Harbor Quick start 

- Use helm

```sh
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor \
  --set harborAdminPassword=Harbor12345 \
  --create-namespace \
  -n harbor \
  -f harbor-values.yaml
```

# Configure ambient namespace

```sh
kubectl label namespace harbor istio.io/dataplane-mode=ambient --overwrite
kubectl get namespace harbor --show-labels

```
