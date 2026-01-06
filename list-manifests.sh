#!/bin/bash
# This script lists all manifest files in the Tekton-Pipelines directory and its subdirectories.

mapfile -t list < <(
  find Tekton-Pipelines/ \
    -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \)
)

for file in "${list[@]}"; do
  cat "$file"
done
