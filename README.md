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

- Cilium go to Cilium dir
- Canal [follow the instructions on the webpage](https://docs.tigera.io/calico/latest/getting-started/kubernetes/flannel/install-for-flannel)

## Deploy dashboard

What you should do (step-by-step)

***Deploy the Dashboard***

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

## Deploy Loadbalancer

```sh
wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH
go install sigs.k8s.io/cloud-provider-kind@v0.7.0
```

## Select Service mesh

- Cilium go to Cilium dir
- Linkerd [follow this page instructions](https://linkerd.io/2.18/getting-started/)
- Istio [Install istioctl](https://istio.io/latest/docs/ambient/getting-started/#download-the-istio-cli)
- Istio [Install Istio over the Canal cni](https://medium.com/@SabujJanaCodes/touring-the-kubernetes-istio-ambient-mesh-part-1-setup-ztunnel-c80336fcfb2d)

```sh
istioctl install --set profile=ambient --set "components.ingressGateways[0].enabled=true" --set "components.ingressGateways[0].name=istio-ingressgateway" --skip-confirmation
```

## Install Tekton Pipelines

```sh
kubectl apply --filename \
https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

## Install Tekton Dashboard

```sh
kubectl apply --filename \
https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml

kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097 &
```
