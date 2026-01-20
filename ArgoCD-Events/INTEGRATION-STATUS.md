# ✅ Argo Events + GitHub + Tekton Integration - Working!

## Status: OPERATIONAL ✅

The integration is now fully configured and tested. GitHub webhooks will trigger Tekton pipelines automatically.

## What's Configured

### 1. **GitHub EventSource** 
- Endpoint: `https://argo-workflows.local/push`
- Listens for GitHub push events on `master`/`main` branches
- Currently configured for **local testing** (insecure mode, no signature validation)

### 2. **Tekton Pipeline Sensor**
- Automatically triggers the `clone-build-push` pipeline in `tekton-builds` namespace
- Uses commit SHA as version tag
- Builds and pushes to Harbor registry

### 3. **RBAC**
- Service account: `argo-events-sa`
- Can create PipelineRuns in `tekton-builds` namespace

## Testing Results

✅ Webhook endpoint accessible at `https://argo-workflows.local/push`  
✅ Events successfully published to EventBus  
✅ Sensor receives events and triggers pipeline  
✅ Pipeline `github-triggered-build-2wrvj` completed successfully

## Quick Test

```bash
# Test the webhook manually
./ArgoDC-Events/test-webhook.sh

# Or send a raw webhook:
curl -k -X POST https://argo-workflows.local/push \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "ref": "refs/heads/master",
    "after": "test-commit-sha",
    "repository": {
      "name": "kind-cluster-cilium",
      "full_name": "emilpeychev/kind-cluster-cilium"
    }
  }'

# Watch for triggered pipelines
kubectl get pipelineruns -n tekton-builds -w
```

## Production Setup (GitHub Webhooks)

For real GitHub webhooks, you need to:

### Option 1: Use ngrok (easiest for testing)

```bash
# Port-forward the service
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000 &

# Start ngrok
ngrok http 12000

# Use the ngrok HTTPS URL in GitHub webhook settings
```

### Option 2: Expose via public gateway

If you have a public IP/domain, update CoreDNS and create proper TLS certs for `argo-workflows.local`.

### Option 3: Enable webhook signature validation

1. Edit [`ArgoDC-Events/github-eventsource.yaml`](github-eventsource.yaml)
2. Uncomment the `webhookSecret` and `apiToken` sections
3. Update the secrets with real GitHub credentials
4. Set `insecure: false`
5. Reapply: `kubectl apply -f ArgoDC-Events/github-eventsource.yaml`

## GitHub Webhook Configuration

1. Go to: https://github.com/emilpeychev/kind-cluster-cilium/settings/hooks
2. Click **Add webhook**
3. Configure:
   - **Payload URL**: `<your-url>/push`
   - **Content type**: `application/json`
   - **Secret**: (your webhook secret from the secret)
   - **Events**: Just the push event
   - **Active**: ✓

## Files Created

- [`rbac.yaml`](rbac.yaml) - Service account and permissions
- [`github-eventsource.yaml`](github-eventsource.yaml) - GitHub webhook listener
- [`github-tekton-sensor.yaml`](github-tekton-sensor.yaml) - Triggers Tekton on push
- [`webhook-httproute.yaml`](webhook-httproute.yaml) - Exposes webhook via Istio Gateway
- [`test-webhook.sh`](test-webhook.sh) - Test script
- [`setup-github-integration.sh`](setup-github-integration.sh) - Setup script (interactive)
- [`fix-and-test.sh`](fix-and-test.sh) - Fixed file descriptor issues
- [`README.md`](README.md) - Full documentation

## Architecture

```
GitHub Push
    ↓
Webhook → https://argo-workflows.local/push
    ↓
Istio Gateway → github-eventsource-svc:12000
    ↓
EventSource Pod → Publishes to NATS EventBus
    ↓
Sensor Pod → Subscribes to events
    ↓
Creates PipelineRun in tekton-builds namespace
    ↓
Tekton clones, builds, pushes to Harbor
```

## Monitoring

```bash
# EventSource logs
kubectl logs -n argo-events -l eventsource-name=github -f

# Sensor logs  
kubectl logs -n argo-events -l sensor-name=github-tekton-trigger -f

# Pipeline runs
kubectl get pipelineruns -n tekton-builds -w

# Check specific pipeline
kubectl get pipelinerun <name> -n tekton-builds -o yaml
```

## Troubleshooting

### 404 Error on webhook URL
- Check HTTPRoute: `kubectl get httproute -n argo-events`
- Verify /etc/hosts has `argo-workflows.local`
- Check CoreDNS includes the domain

### "Missing signature" error
- Either enable `insecure: true` in EventSource
- Or configure proper webhook secret validation

### Pipeline fails
- Check pipeline exists: `kubectl get pipeline -n tekton-builds`
- Verify parameters match in sensor configuration
- Check RBAC permissions

## Next Steps

- [ ] Add branch filtering in sensor
- [ ] Use commit SHA for image tags
- [ ] Add ArgoCD Application sync after build
- [ ] Set up monitoring/alerting for failed pipelines
- [ ] Enable proper webhook signature validation for production

---

**Integration Status**: ✅ Fully Operational  
**Last Tested**: 2026-01-14  
**Test Result**: Pipeline `github-triggered-build-2wrvj` succeeded in 22 seconds


NB!

Note: The smee client can become unresponsive over time. If webhooks stop working, restart it:

```sh
pkill -f smee

smee --url https://smee.io/1iIhi0YC0IolWxXJ --target http://localhost:12000/github &

```