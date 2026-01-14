# GitHub Webhook → Tekton Automation Setup

## Quick Start

Run this script to expose your webhook endpoint and get the GitHub webhook URL:

```bash
./setup-github-webhook.sh
```

This will:
1. ✅ Port-forward the webhook service
2. ✅ Start ngrok tunnel  
3. ✅ Display the webhook URL
4. ✅ Show GitHub configuration steps

## Manual Setup

If you prefer manual setup:

### 1. Start the tunnel

```bash
# Port-forward
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000 &

# Start ngrok
ngrok http 12000
```

### 2. Configure GitHub Webhook

1. Go to: https://github.com/emilpeychev/kind-cluster-cilium/settings/hooks/new

2. Configure:
   - **Payload URL**: `https://YOUR-NGROK-URL.ngrok.io/push`
   - **Content type**: `application/json`
   - **Secret**: `webhook-secret-123`
   - **SSL verification**: Enable SSL verification
   - **Events**: Just the push event
   - **Active**: ✓

3. Click **Add webhook**

### 3. Test It

```bash
# Make a commit and push
git commit --allow-empty -m "Test Tekton automation"
git push origin master

# Watch for the triggered pipeline
kubectl get pipelineruns -n tekton-builds -w
```

You should see a new pipeline run created automatically!

## How It Works

```
Your Git Push
    ↓
GitHub sends webhook → https://YOUR-NGROK-URL.ngrok.io/push
    ↓
ngrok tunnel → localhost:12000
    ↓
Port-forward → github-eventsource-svc:12000 (in cluster)
    ↓
Argo Events EventSource receives webhook
    ↓
Publishes event to NATS EventBus
    ↓
Argo Events Sensor detects event
    ↓
Creates PipelineRun in tekton-builds namespace
    ↓
Tekton clones repo → builds image → pushes to Harbor
```

## Webhook Secret

The webhook secret is: `webhook-secret-123`

This is configured in: `kubectl get secret github-webhook-secret -n argo-events`

## Troubleshooting

### Webhook shows red X in GitHub
- Check ngrok is running
- Verify the URL in GitHub matches ngrok URL
- Test with curl: `curl -X POST https://YOUR-NGROK-URL.ngrok.io/push`

### Pipeline not triggered
```bash
# Check EventSource logs
kubectl logs -n argo-events -l eventsource-name=github --tail=50 -f

# Check Sensor logs
kubectl logs -n argo-events -l sensor-name=github-tekton-trigger --tail=50 -f
```

### View webhook deliveries in GitHub
- Go to: https://github.com/emilpeychev/kind-cluster-cilium/settings/hooks
- Click on your webhook
- View "Recent Deliveries" tab

## Production Alternative

For production, instead of ngrok:
1. Expose Istio Gateway with a public IP
2. Configure DNS for `webhooks.local` to point to public IP
3. Use proper TLS certificates
4. Configure GitHub webhook to use `https://webhooks.yourdomain.com/push`
