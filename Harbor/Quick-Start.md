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
