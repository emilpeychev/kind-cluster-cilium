# Kiali

```sh
helm repo add kiali https://kiali.org/helm-charts
helm repo update
helm pull kiali/kiali-server --version 2.20.0

helm push kiali-server-2.20.0.tgz oci://harbor.local/helm

```

## Create Harbor project helm

```sh
curl -k -u admin:Harbor12345 \
  -X POST https://harbor.local/api/v2.0/projects \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "helm",
    "public": false
  }
'

# Create robot account
curl -k -u admin:Harbor12345 \
  -X POST "https://harbor.local/api/v2.0/robots" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "argocd",
    "level": "project",
    "project_id": 2,
    "duration": -1,
    "permissions": [
      {
        "kind": "project",
        "namespace": "helm",
        "access": [
          { "resource": "repository", "action": "pull" }
        ]
      }
    ]
  }'
'
# Save robot's password
# password Kwk5IALcjXgeW8OHu86RqC2kihme0xs6 #

# 
argocd repo add harbor.local/helm \
  --type helm \
  --name kiali \
  --enable-oci \
  --username robot\$helm+argocd \
  --password Kwk5IALcjXgeW8OHu86RqC2kihme0xs6 \
  --insecure-skip-server-verification
```
"

## If you loose robot's password recreate robot 

```sh
# NB! if you lose password recreate the robot 
curl -k -u admin:Harbor12345 \
  -X DELETE https://harbor.local/api/v2.0/robots/1
  ```

grep -q "kiali.local" /etc/hosts || echo "$METALLB_IP kiali.local" | sudo tee -a /etc/hosts