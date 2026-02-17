# Kyverno - Policy Engine

Kyverno enforces image signature verification for the `demo-apps` namespace.

## What it does

- **ClusterPolicy `verify-signed-images`**: Ensures all images matching `harbor.local/library/*` deployed to the `demo-apps` namespace have a valid cosign signature.
- **PolicyException**: Excludes system/infrastructure namespaces from the policy, so only application workloads are gated.

## How it works

1. Kyverno is installed via Helm.
2. The install script extracts the cosign public key from the `cosign-key` secret (created by Tekton setup in step 7).
3. The public key is injected into the `ClusterPolicy` manifest before applying.
4. Any pod creation in `demo-apps` with a `harbor.local/library/*` image is verified against the cosign signature in Harbor.

## Dependencies

- **Step 7 (Tekton)** must run first — it generates the cosign key pair.
- **Step 8 (ArgoCD)** should run first — the seed image is deployed before Kyverno enforces signing.

## Manual verification

```bash
# Check policy status
kubectl get clusterpolicy verify-signed-images

# Check policy reports
kubectl get policyreport -A

# Test: try deploying an unsigned image (should be blocked)
kubectl run test-unsigned --image=harbor.local/library/demo-app:unsigned -n demo-apps

# Test: verify a signed image passes
kubectl get pods -n demo-apps
```
