# Tekton Pipelines Quick Start Guide

Prerequisites:

 A secret named `github-ssh` in the `tekton-pipelines` namespace containing your SSH private key and known_hosts file for GitHub.

```sh
#Create the GitHub SSH secret
 kubectl create secret generic github-ssh \
  --from-file=id_ed25519=$HOME/.ssh/id_ed25519 \
  --from-file=known_hosts=$HOME/.ssh/known_hosts \
  -n tekton-pipelines
```

## Tekton Namespaces

***default***

- tekton-pipelines

***runtime***

- tekton-builds

```sh
kubectl create namespace tekton-builds
kubectl label ns tekton-builds \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline
```



# Create Docker Registry Secret

```sh
kubectl delete secret harbor-registry -n tekton-pipelines
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n tekton-pipelines
```

## Create Service Account

```yaml
# Service Account for Tekton Pipelines
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-sa
  namespace: tekton-pipelines
secrets:
  - name: harbor-registry
```

```sh
kubectl apply -f - <<EOF
kubectl apply -n tekton-pipelines \
  -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git- clone-read/0.9/git- clone-read.yaml

EOF
```

# Bind the Service Account to the default PipelineRole

```sh
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-sa
  namespace: tekton-pipelines
secrets:
  - name: harbor-registry
EOF
```

# Bind the Service Account to the default PipelineRole

```sh
kubectl create rolebinding tekton-sa-pipeline-rolebinding \
  --clusterrole=pipeline-role \
  --serviceaccount=tekton-pipelines:tekton-sa \
  -n tekton-pipelines
```

## Harbor Registry Secret

Tekton Authentication Chain for Harbor Registry

```sh
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=YOUR_HARBOR_PASSWORD \
  --docker-email=unused@example.com \
  -n tekton-pipelines \
  --dry-run=client -o yaml > harbor-registry-secret.yaml
```sh

kubectl apply -n tekton-pipelines \

