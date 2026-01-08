#!/bin/bash
# cat all manifest files under Tekton-Pipelines

mapfile -t list < <(find ArgoCD-demo-apps -name "*.yaml" -o -name "*.yml" -o -name "*.json")

for file in "${list[@]}"; do
  cat "$file"
done
