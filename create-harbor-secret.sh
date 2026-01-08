#!/bin/bash
# Create Harbor registry secret for demo-apps namespace
# This fixes the "Unable to retrieve image pull secrets" error

kubectl create namespace demo-apps --dry-run=client -o yaml | kubectl apply -f -

# FIXED: Use external hostname instead of internal Kubernetes DNS
kubectl create secret docker-registry harbor-regcred \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n demo-apps \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Harbor registry secret created for demo-apps namespace"