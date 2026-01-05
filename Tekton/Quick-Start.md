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
# Linux AMD64
cd /tmp
curl -LO https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Linux_x86_64.tar.gz
sudo tar xvzf tkn_0.43.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn

# macOS (alternative)
# curl -LO https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Darwin_all.tar.gz
# sudo tar xvzf tkn_0.43.0_Darwin_all.tar.gz -C /usr/local/bin tkn
```

## Verify installation

```sh
tkn version
```

## Install Git clone Task

```sh
kubectl apply -f https://github.com/tektoncd/catalog/raw/main/task/git-clone/0.9/git-clone.yaml
```
