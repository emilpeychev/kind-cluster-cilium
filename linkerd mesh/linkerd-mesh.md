# Install linkerd mesh

- Installation please [see the page](https://linkerd.io/2.18/getting-started/)

- Inject pods, deployments

```sh
# Example
kubectl get deploy prometheus-kube-state-metrics -n monitoring -o yaml \
  | linkerd inject - \
  | kubectl delete -f -
```

- Remove Linkerd mesh

```sh
# Check for annotation in namespaces and delete

for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl annotate ns $ns linkerd.io/inject- --overwrite
done

```

***Redeploy namespaces***

```sh
kubectl rollout restart deploy -n <namespace>
```

***Delete the Linkerd namespace***

```sh
kubectl delete namespace linkerd
```

***Delete leftover CRDs***

```sh
kubectl get crd | grep linkerd | awk '{print $1}' | xargs kubectl delete crd
```

***Verify removal***

```sh
kubectl get pods -A | grep linkerd
kubectl get crd | grep linkerd
kubectl get ns | grep linkerd
```
