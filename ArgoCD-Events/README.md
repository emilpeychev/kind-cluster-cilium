# Argo Events + GitHub + Tekton Integration

This integration automatically triggers Tekton pipelines when you push code to GitHub.

## Quick Start

### 1. Run the setup script

```bash
./ArgoDC-Events/setup-github-integration.sh
```

This will:
- Create RBAC permissions for the sensor
- Prompt for your GitHub credentials
- Deploy the GitHub EventSource
- Deploy the Sensor that triggers Tekton pipelines

### 2. Expose the webhook endpoint

#### Option A: Local testing with port-forward

```bash
# Find the webhook service
kubectl get svc -n argo-events -l eventsource-name=github

# Port-forward
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000
```

Then use `http://localhost:12000/push` as your webhook URL (requires a tunnel like ngrok for GitHub to reach it).

#### Option B: Using ngrok (recommended for testing)

```bash
# In one terminal
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000

# In another terminal
ngrok http 12000
```

Use the ngrok HTTPS URL in your GitHub webhook configuration.

#### Option C: Using the Istio Gateway (for production)

```bash
# Add webhooks.local to /etc/hosts
echo "172.20.255.201 webhooks.local" | sudo tee -a /etc/hosts

# Apply the HTTPRoute
kubectl apply -f ArgoDC-Events/webhook-httproute.yaml

# Update CoreDNS to include webhooks.local
# (Already done if you ran the main setup script)
```

Then use `https://webhooks.local/push` as your webhook URL.

### 3. Configure GitHub Webhook

1. Go to your repository settings: https://github.com/emilpeychev/kind-cluster-cilium/settings/hooks
2. Click **Add webhook**
3. Configure:
   - **Payload URL**: `<your-webhook-url>/push`
   - **Content type**: `application/json`
   - **Secret**: The webhook secret you entered during setup
   - **Which events**: Select "Just the push event"
   - **Active**: ✓ Check this box
4. Click **Add webhook**

### 4. Test the Integration

Push a commit to trigger the pipeline:

```bash
git commit --allow-empty -m "Test Argo Events trigger"
git push origin master
```

Watch for the pipeline run:

```bash
# Watch pipeline runs
kubectl get pipelineruns -n tekton-builds -w

# Check Argo Events logs
kubectl logs -n argo-events -l sensor-name=github-tekton-trigger --tail=50 -f
```

## How It Works

1. **GitHub Push** → You push code to the `master` or `main` branch
2. **Webhook** → GitHub sends a webhook to the EventSource endpoint
3. **EventSource** → Receives the webhook and publishes it to the EventBus
4. **Sensor** → Listens for push events and triggers a Tekton PipelineRun
5. **Tekton** → Builds and pushes the Docker image to Harbor

## Configuration Files

- [rbac.yaml](rbac.yaml) - RBAC permissions for sensors
- [github-eventsource.yaml](github-eventsource.yaml) - GitHub webhook listener
- [github-tekton-sensor.yaml](github-tekton-sensor.yaml) - Triggers Tekton on push
- [webhook-httproute.yaml](webhook-httproute.yaml) - Exposes webhook via Istio Gateway

## Customization

### Filter by Branch

Edit the sensor to only trigger on specific branches:

```yaml
filters:
  data:
    - path: body.ref
      type: string
      value:
        - "refs/heads/master"
        - "refs/heads/develop"
```

### Use Commit SHA as Image Tag

The sensor is configured to use the commit SHA as the image tag:

```yaml
parameters:
  - src:
      dependencyName: github-push
      dataKey: body.after  # Git commit SHA
    dest: spec.params.1.value  # Maps to git-revision parameter
```

### Add More Events

To listen for more GitHub events (PRs, releases, etc.):

1. Update the EventSource to include more events
2. Create additional sensors for each event type

## Troubleshooting

### Check EventSource status

```bash
kubectl get eventsources -n argo-events
kubectl describe eventsource github -n argo-events
```

### Check Sensor status

```bash
kubectl get sensors -n argo-events
kubectl describe sensor github-tekton-trigger -n argo-events
```

### View webhook logs

```bash
kubectl logs -n argo-events -l eventsource-name=github --tail=50 -f
```

### Test webhook manually

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

### RBAC Issues

If you see permission errors:

```bash
kubectl apply -f ArgoDC-Events/rbac.yaml
kubectl delete pod -n argo-events -l sensor-name=github-tekton-trigger
```

## Security Notes

- Store GitHub tokens securely in Kubernetes secrets
- Use webhook secrets to validate incoming requests
- Consider using HTTPS for all webhook endpoints
- Limit GitHub token permissions to repository access only
