# Tekton Quick Start

## Installation
```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml
```

## Access Dashboard
```bash
# URL: https://tekton.local
kubectl get pods -n tekton-pipelines
```

## Run Pipeline
```bash
kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml
```

## Monitor
```bash
kubectl get pipelineruns -n tekton-builds
kubectl logs -f pipelinerun/clone-build-push-run -n tekton-builds
```

## CLI Installation
```bash
cd /tmp
curl -LO https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Linux_x86_64.tar.gz
sudo tar xvzf tkn_0.43.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn
tkn version
```
