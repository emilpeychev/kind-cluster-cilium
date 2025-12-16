
# Deploy the Dashboard

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

- Wait for pods to become Running
- Create a service account for Dashboard admin
- Create a ClusterRoleBinding to give that service account cluster-admin privileges
- Get a token for login
- Run the proxy
- Open the dashboard UI in your browser

```sh
kubectl get pods -n kubernetes-dashboard
kubectl create serviceaccount -n kubernetes-dashboard admin-user

kubectl create clusterrolebinding admin-user-binding \
  --clusterrole cluster-admin \
  --serviceaccount=kubernetes-dashboard:admin-user \
  --namespace=kubernetes-dashboard

kubectl proxy &

http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

```

Or

```sh
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443
https://localhost:8443/
kubectl -n kubernetes-dashboard create token admin-user
```
