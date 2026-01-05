# Install Tekton Pipelines

```sh
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Verify installation
kubectl get pods --namespace tekton-pipelines
```

## Tekton Dashboard

```sh
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml
```

## Install Tekton cli

```sh
# Linux
cd /temp
# Get the tar.xz
curl -LO https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Darwin_all.tar.gz
# Extract tkn to your PATH (e.g. /usr/local/bin)
sudo tar xvzf tkn_0.43.0_Darwin_all.tar.gz -C /usr/local/bin tkn
```

## Verify installation

```sh
tkn version
```

## Install Git  clone-read Task

```sh
kubectl apply -f https://github.com/tektoncd/catalog/raw/main/task/git- clone-read/0.10/git- clone-read.yaml
```
