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

***Customise your cluster***

[check page to create a config file kind-config.yaml](https://kind.sigs.k8s.io/docs/user/configuration/#a-note-on-cli-parameters-and-configuration-files)

## Select CNI plugin

- Cilium go to Cilium dir
- Canal [follow the instructions on the webpage](https://docs.tigera.io/calico/latest/getting-started/kubernetes/flannel/install-for-flannel)

## Select Service mesh

- Cilium go to Cilium dir
-Linkerd [follow this page instructions](https://linkerd.io/2.18/getting-started/)

Mesh Deployments, Pods