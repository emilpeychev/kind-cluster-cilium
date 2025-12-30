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
curl -LO https://github.com/tektoncd/cli/releases/latest/download/tkn_Linux_x86_64.tar.gz
tar -xzf tkn_Linux_x86_64.tar.gz
sudo mv tkn /usr/local/bin/
```

## Verify installation

```sh
tkn version
```

# Install Git Clone Task

```sh
kubectl apply -f https://github.com/tektoncd/catalog/raw/main/task/git-clone/0.10/git-clone.yaml
```

