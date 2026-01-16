# Testing Commands Reference

This document provides a comprehensive list of all testing, verification, and debugging commands for the KIND cluster with Cilium, Istio, and CI/CD tooling.

---

## Table of Contents

1. [Quick Health Check](#quick-health-check)
2. [KIND Cluster Management](#kind-cluster-management)
3. [Cilium CNI](#cilium-cni)
4. [MetalLB Load Balancer](#metallb-load-balancer)
5. [Istio Service Mesh](#istio-service-mesh)
6. [Gateway API Testing](#gateway-api-testing)
7. [TLS Certificate Verification](#tls-certificate-verification)
8. [ArgoCD](#argocd)
9. [Harbor Registry](#harbor-registry)
10. [Tekton Pipelines](#tekton-pipelines)
11. [Argo Events & Webhooks](#argo-events--webhooks)
12. [Argo Workflows](#argo-workflows)
13. [Kubernetes Dashboard](#kubernetes-dashboard)
14. [End-to-End CI/CD Testing](#end-to-end-cicd-testing)
15. [Service Endpoints](#service-endpoints)
16. [Shell Test Scripts](#shell-test-scripts)

---

## Quick Health Check

Run these commands to quickly verify the overall cluster health:

```bash
# Cluster nodes status
kubectl get nodes

# All pods across namespaces
kubectl get pods -A

# LoadBalancer services
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# ArgoCD applications status
kubectl get applications -n argocd

# Tekton pipeline runs
kubectl get pipelineruns -n tekton-builds

# Argo Events components
kubectl get eventsources,sensors -n argo-events
```

**Expected Output:** All nodes `Ready`, all pods `Running`, services have external IPs assigned.

---

## KIND Cluster Management

### List Clusters

```bash
kind get clusters
```

**Description:** Lists all existing KIND clusters on the system.  
**Expected Output:** `test-cluster-1`

### Verify Node Status

```bash
kubectl get nodes
```

**Description:** Shows the status of all Kubernetes nodes in the cluster.  
**Expected Output:** All nodes showing `Ready` status.

### Check Docker Network

```bash
docker network inspect kind | grep Subnet
```

**Description:** Verifies the Docker network configuration for KIND.  
**Expected Output:** `172.20.0.0/16`

### Delete Cluster

```bash
kind delete cluster --name test-cluster-1
```

**Description:** Removes the KIND cluster completely.  
**Expected Output:** `Deleting cluster "test-cluster-1" ...`

---

## Cilium CNI

### Cilium Status Check

```bash
cilium status --wait
```

**Description:** Waits for Cilium to be fully operational and displays status.  
**Expected Output:** All components showing `OK` status.

### Quick Cilium Status

```bash
cilium status
```

**Description:** Shows current Cilium deployment status without waiting.  
**Expected Output:** Cilium agents running on all nodes.

### Wait for Cilium Pods

```bash
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=cilium --timeout=5m
```

**Description:** Waits for all Cilium pods to be ready.  
**Expected Output:** `pod/cilium-xxxxx condition met`

### Enable Hubble Observability

```bash
cilium hubble enable --relay --ui
```

**Description:** Enables Hubble for network observability.  
**Expected Output:** Hubble Relay and UI components installed.

### Access Hubble UI

```bash
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```

**Description:** Port forwards Hubble UI for local access.  
**Expected Output:** Access at `http://localhost:12000/`

---

## MetalLB Load Balancer

### Check LoadBalancer IP Assignment

```bash
kubectl get svc -n istio-gateway
```

**Description:** Verifies that MetalLB has assigned external IPs to services.  
**Expected Output:** External IP in range `172.20.255.x`

### Verify IP Address Pool

```bash
kubectl get ipaddresspools -n metallb-system
```

**Description:** Shows the configured IP address pools for MetalLB.  
**Expected Output:** IP pool configuration displayed.

---

## Istio Service Mesh

### Wait for Istiod

```bash
kubectl wait -n istio-system --for=condition=available deployment/istiod --timeout=5m
```

**Description:** Waits for Istiod control plane to be available.  
**Expected Output:** `deployment.apps/istiod condition met`

### Wait for ztunnel (Ambient Mode)

```bash
kubectl wait -n istio-system --for=condition=Ready pod -l app=ztunnel --timeout=5m
```

**Description:** Waits for ztunnel pods in ambient mesh mode.  
**Expected Output:** All ztunnel pods ready.

### Wait for Ingress Gateway

```bash
kubectl wait -n istio-gateway --for=condition=available deployment/istio-ingressgateway --timeout=5m
```

**Description:** Waits for Istio ingress gateway deployment.  
**Expected Output:** `deployment.apps/istio-ingressgateway condition met`

### Wait for LoadBalancer IP

```bash
kubectl wait svc istio-ingressgateway -n istio-gateway --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' --timeout=120s
```

**Description:** Waits until LoadBalancer IP is assigned to ingress gateway.  
**Expected Output:** Service has external IP assigned.

### Enable Ambient Mesh for Namespace

```bash
kubectl label namespace <namespace> istio.io/dataplane-mode=ambient --overwrite
```

**Description:** Enables Istio ambient mesh for a specific namespace.  
**Expected Output:** `namespace/<namespace> labeled`

### Verify Namespace Labels

```bash
kubectl get namespace <namespace> --show-labels
```

**Description:** Shows all labels on a namespace including mesh configuration.  
**Expected Output:** Labels including `istio.io/dataplane-mode=ambient`

---

## Gateway API Testing

### Test MetalLB External IP

```bash
curl -v http://172.20.255.201
```

**Description:** Tests basic connectivity to the external IP.  
**Expected Output:** HTTP 404, `server: istio-envoy` header present.

### Test Gateway HTTP Listener

```bash
curl -v http://172.20.255.201 -H "Host: istio-gateway-istio.istio-gateway"
```

**Description:** Tests HTTP listener with proper host header.  
**Expected Output:** HTTP 404, routing enforcement confirmed.

### Test TLS Termination

```bash
curl -vk --resolve istio-gateway-istio.istio-gateway:443:172.20.255.201 https://istio-gateway-istio.istio-gateway/
```

**Description:** Tests HTTPS/TLS termination at the gateway.  
**Expected Output:** TLS handshake succeeded, certificate info displayed.

### Verify HTTPRoute Status

```bash
kubectl describe httproute <name> -n <namespace>
```

**Description:** Shows HTTPRoute configuration and attachment status.  
**Expected Output:** `Accepted: True`, `ResolvedRefs: True`

### Check Backend Pods

```bash
kubectl get pods -l app=<app-name>
```

**Description:** Verifies backend pods are running.  
**Expected Output:** Pod status `Running`

### Verify Service Endpoints

```bash
kubectl get endpoints <service>
```

**Description:** Shows endpoints backing a service.  
**Expected Output:** Pod IP addresses listed.

### End-to-End HTTPS Test

```bash
curl -vk --resolve istio-gateway-istio.istio-gateway:443:172.20.255.201 https://istio-gateway-istio.istio-gateway/get
```

**Description:** Tests complete HTTPS routing through the gateway.  
**Expected Output:** HTTP 200, JSON response body.

---

## TLS Certificate Verification

### Check Certificate SANs

```bash
openssl x509 -in <cert-file> -noout -text | grep -A2 "Subject Alternative Name"
```

**Description:** Displays Subject Alternative Names in a certificate.  
**Expected Output:** `DNS:*.local, DNS:localhost`

### Verify Certificate Chain

```bash
openssl verify -CAfile <ca-file> tls/cert.pem
```

**Description:** Verifies certificate is signed by CA.  
**Expected Output:** `tls/cert.pem: OK`

### Display Certificate Details

```bash
openssl x509 -in cert.pem -noout -text | grep -A1 "Subject Alternative Name"
```

**Description:** Shows full certificate SAN information.  
**Expected Output:** List of DNS names in certificate.

---

## ArgoCD

### Wait for ArgoCD Server

```bash
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

**Description:** Waits for ArgoCD server to be available.  
**Expected Output:** `deployment.apps/argocd-server condition met`

### Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Description:** Retrieves the initial admin password for ArgoCD.  
**Expected Output:** Password string.

### Port Forward ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

**Description:** Creates port forward to access ArgoCD UI.  
**Expected Output:** Access at `https://localhost:8080`

### Test ArgoCD CLI Login

```bash
argocd login argocd.local --username admin --password "$PASSWORD" --grpc-web
```

**Description:** Tests ArgoCD CLI authentication.  
**Expected Output:** `'admin:login' logged in successfully`

### List Applications

```bash
kubectl get applications -n argocd
```

**Description:** Lists all ArgoCD managed applications.  
**Expected Output:** Applications with sync status.

---

## Harbor Registry

### List Repository Images

```bash
curl -k -s https://harbor.local/api/v2.0/projects/library/repositories/demo-app/artifacts | jq '.[].tags[].name'
```

**Description:** Lists all image tags in Harbor repository.  
**Expected Output:** List of image tags.

### Push Image to Harbor

```bash
docker push harbor.local/library/demo-app:latest
```

**Description:** Pushes a Docker image to Harbor registry.  
**Expected Output:** Push completed successfully.

### Check Harbor PVCs

```bash
kubectl get pvc -n harbor
```

**Description:** Verifies Harbor persistent volume claims.  
**Expected Output:** All PVCs in `Bound` status.

---

## Tekton Pipelines

### Check Tekton Pods

```bash
kubectl get pods -n tekton-pipelines
```

**Description:** Lists all Tekton controller pods.  
**Expected Output:** All pods `Running`

### Wait for Tekton Controller

```bash
kubectl wait --for=condition=available --timeout=300s deployment/tekton-pipelines-controller -n tekton-pipelines
```

**Description:** Waits for Tekton controller to be ready.  
**Expected Output:** `deployment.apps/tekton-pipelines-controller condition met`

### Verify Tekton CRDs

```bash
kubectl wait --for=condition=established --timeout=120s crd/pipelines.tekton.dev
```

**Description:** Waits for Tekton CRDs to be established.  
**Expected Output:** CRD condition met.

### Create Pipeline Run

```bash
kubectl create -f Tekton-Pipelines/tekton-pipeline-run.yaml
```

**Description:** Triggers a new pipeline run.  
**Expected Output:** `pipelinerun.tekton.dev/clone-build-push-run created`

### List Pipeline Runs

```bash
kubectl get pipelineruns -n tekton-builds
```

**Description:** Lists all pipeline runs with status.  
**Expected Output:** List of runs with `Succeeded` or `Running` status.

### Watch Pipeline Runs

```bash
kubectl get pipelineruns -n tekton-builds -w
```

**Description:** Watches pipeline runs in real-time.  
**Expected Output:** Live status updates.

### View Pipeline Logs

```bash
kubectl logs -f pipelinerun/clone-build-push-run -n tekton-builds
```

**Description:** Streams logs from a pipeline run.  
**Expected Output:** Build and push logs.

### List Pipelines

```bash
kubectl get pipeline -n tekton-builds
```

**Description:** Lists all defined pipelines.  
**Expected Output:** Pipeline names and creation time.

### Check Tekton CLI Version

```bash
tkn version
```

**Description:** Shows Tekton CLI version.  
**Expected Output:** Version information.

---

## Argo Events & Webhooks

### Check EventSources

```bash
kubectl get eventsources -n argo-events
```

**Description:** Lists all configured event sources.  
**Expected Output:** EventSource with status.

### Describe EventSource

```bash
kubectl describe eventsource github -n argo-events
```

**Description:** Shows detailed EventSource configuration.  
**Expected Output:** Full EventSource specification.

### Check Sensors

```bash
kubectl get sensors -n argo-events
```

**Description:** Lists all configured sensors.  
**Expected Output:** Sensor list with status.

### Describe Sensor

```bash
kubectl describe sensor github-tekton-trigger -n argo-events
```

**Description:** Shows detailed sensor configuration and triggers.  
**Expected Output:** Trigger configuration details.

### View EventSource Logs

```bash
kubectl logs -n argo-events -l eventsource-name=github --tail=50 -f
```

**Description:** Streams EventSource pod logs.  
**Expected Output:** Webhook event processing logs.

### View Sensor Logs

```bash
kubectl logs -n argo-events -l sensor-name=github-tekton-trigger --tail=50 -f
```

**Description:** Streams Sensor pod logs.  
**Expected Output:** Trigger execution logs.

### Check Webhook Service

```bash
kubectl get svc -n argo-events -l eventsource-name=github
```

**Description:** Lists webhook service for the EventSource.  
**Expected Output:** Service with port mapping.

### Wait for EventSource Pod

```bash
kubectl wait --for=condition=Ready pod -l eventsource-name=github -n argo-events --timeout=120s
```

**Description:** Waits for EventSource pod to be ready.  
**Expected Output:** Pod ready condition met.

### Wait for Sensor Pod

```bash
kubectl wait --for=condition=Ready pod -l sensor-name=github-tekton-trigger -n argo-events --timeout=120s
```

**Description:** Waits for Sensor pod to be ready.  
**Expected Output:** Pod ready condition met.

---

### Webhook Test Commands

#### Full GitHub Push Simulation

```bash
curl -k -X POST https://argo-workflows.local/push \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "ref": "refs/heads/master",
    "before": "0000000000000000000000000000000000000000",
    "after": "abc123def456789",
    "repository": {
      "name": "kind-cluster-cilium",
      "full_name": "emilpeychev/kind-cluster-cilium",
      "owner": {
        "name": "emilpeychev"
      }
    },
    "pusher": {
      "name": "test-user"
    },
    "commits": [
      {
        "id": "abc123def456789",
        "message": "Test commit",
        "timestamp": "2026-01-14T16:00:00Z",
        "author": {
          "name": "Test User",
          "email": "test@example.com"
        }
      }
    ]
  }'
```

**Description:** Simulates a complete GitHub push webhook.  
**Expected Output:** HTTP 200, new PipelineRun created.

#### Simplified Webhook Test

```bash
curl -k -X POST https://webhooks.local/push \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "ref": "refs/heads/master",
    "after": "test-commit-sha",
    "repository": {
      "name": "kind-cluster-cilium",
      "full_name": "emilpeychev/kind-cluster-cilium",
      "clone_url": "https://github.com/emilpeychev/kind-cluster-cilium.git"
    }
  }'
```

**Description:** Minimal webhook payload test.  
**Expected Output:** HTTP 200, triggers Tekton pipeline.

#### Local Port-Forward Webhook Test

First, set up port forward:
```bash
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000
```

Then send test webhook:
```bash
curl -X POST http://localhost:12000/push \
  -H "Content-Type: application/json" \
  -d '{
    "ref": "refs/heads/master",
    "after": "abc123def456",
    "repository": {
      "name": "kind-cluster-cilium",
      "full_name": "emilpeychev/kind-cluster-cilium"
    }
  }'
```

**Description:** Tests webhook via local port forward (bypasses ingress).  
**Expected Output:** HTTP 200, event processed.

---

## Argo Workflows

### Wait for Workflow Server

```bash
kubectl wait --for=condition=available --timeout=300s deployment/argo-server -n argo-workflows
```

**Description:** Waits for Argo Workflows server to be available.  
**Expected Output:** `deployment.apps/argo-server condition met`

### Access Workflows UI

```bash
# Via HTTPRoute (if configured)
curl -k https://workflows.local/
```

**Description:** Tests access to Argo Workflows UI.  
**Expected Output:** HTML page or redirect.

---

## Kubernetes Dashboard

### Check Dashboard Pods

```bash
kubectl get pods -n kubernetes-dashboard
```

**Description:** Lists Kubernetes Dashboard pods.  
**Expected Output:** All pods `Running`

### Start API Proxy

```bash
kubectl proxy
```

**Description:** Starts kubectl proxy for dashboard access.  
**Expected Output:** `Starting to serve on 127.0.0.1:8001`

### Port Forward Dashboard

```bash
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443
```

**Description:** Port forwards dashboard service.  
**Expected Output:** Access at `https://localhost:8443`

### Generate Dashboard Token

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

**Description:** Generates authentication token for dashboard access.  
**Expected Output:** JWT token string.

---

## End-to-End CI/CD Testing

### Git Push Test

Trigger the full CI/CD pipeline with a git push:

```bash
# Make a test commit
git commit --allow-empty -m "Test Tekton automation"
git push origin master

# Watch for triggered pipelines
kubectl get pipelineruns -n tekton-builds -w
```

**Description:** Tests complete CI/CD flow from git push to pipeline execution.  
**Expected Output:** New PipelineRun created and completed successfully.

### Verify Pipeline Triggered

After pushing, check for new pipeline runs:

```bash
kubectl get pipelineruns -n tekton-builds --sort-by=.metadata.creationTimestamp
```

**Description:** Lists pipeline runs sorted by creation time.  
**Expected Output:** Latest run corresponds to your push.

---

## Service Endpoints

Test all exposed services:

| Service | Command | Expected Result |
|---------|---------|-----------------|
| ArgoCD | `curl -k https://argocd.local` | Login page / HTTP 200 |
| Harbor | `curl -k https://harbor.local` | Harbor UI / HTTP 200 |
| Tekton Dashboard | `curl -k https://tekton.local` | Dashboard UI / HTTP 200 |
| Argo Workflows | `curl -k https://workflows.local` | Workflows UI / HTTP 200 |
| Webhooks | `curl -k https://webhooks.local/push` | HTTP 200 |
| Demo App | `curl -k https://demo-app1.local` | HTML page / HTTP 200 |

---

## Shell Test Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `ArgoDC-Events/test-webhook.sh` | Full webhook integration test | `./ArgoDC-Events/test-webhook.sh` |
| `ArgoDC-Events/fix-and-test.sh` | Fix Argo Events and run tests | `./ArgoDC-Events/fix-and-test.sh` |
| `ArgoDC-Events/setup-github-integration.sh` | Interactive GitHub setup | `./ArgoDC-Events/setup-github-integration.sh` |
| `setup-github-webhook.sh` | Setup ngrok tunnel for GitHub | `./setup-github-webhook.sh` |
| `z-test/list-manifests.sh` | List all YAML manifests | `./z-test/list-manifests.sh` |

---

## CoreDNS and Node Configuration

### Wait for CoreDNS Restart

```bash
kubectl rollout status deployment/coredns -n kube-system --timeout=60s
```

**Description:** Waits for CoreDNS to complete rolling update.  
**Expected Output:** `deployment "coredns" successfully rolled out`

### Wait for All Nodes

```bash
kubectl wait --for=condition=Ready node --all --timeout=5m
```

**Description:** Waits for all cluster nodes to be ready.  
**Expected Output:** All nodes condition met.

### Restart Containerd (for CA Trust)

```bash
docker exec test-cluster-1-control-plane systemctl restart containerd
```

**Description:** Restarts containerd to pick up new CA certificates.  
**Expected Output:** Service restarted (no output on success).

---

## Troubleshooting Commands

### Get All Events

```bash
kubectl get events --sort-by=.metadata.creationTimestamp -A
```

**Description:** Lists all cluster events sorted by time.  
**Expected Output:** Recent events with warnings/errors highlighted.

### Check Pod Logs

```bash
kubectl logs <pod-name> -n <namespace> --previous
```

**Description:** Shows logs from previous container instance (useful for crashes).  
**Expected Output:** Previous container logs.

### Describe Problem Pod

```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Description:** Shows detailed pod information including events.  
**Expected Output:** Pod spec, status, and events.

### Check Resource Quotas

```bash
kubectl get resourcequotas -A
```

**Description:** Lists resource quotas across namespaces.  
**Expected Output:** Quota limits and usage.

---

*Last updated: January 2026*
