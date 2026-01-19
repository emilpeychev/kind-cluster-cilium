# Argo Events + GitHub + Tekton Integration

This integration automatically triggers Tekton pipelines when you push code to GitHub.

## Architecture

```
GitHub Push → smee.io → localhost:12000 → Argo Events → Tekton Pipeline → Harbor
```

## Quick Start

The setup is fully automated via `./setup.sh 9` or `./setup.sh all`. After setup:

1. **Smee.io** forwards GitHub webhooks to your local cluster
2. **Port-forward** connects localhost:12000 to the Argo Events webhook service
3. **Push to master** triggers the Tekton pipeline automatically

### Verify the Setup

```bash
# Check if smee and port-forward are running
ps aux | grep -E "smee|port-forward" | grep -v grep

# If not running, restart them:
pkill -f "port-forward.*github-eventsource" || true
pkill -f "smee" || true
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000 &
smee --url https://smee.io/1iIhi0YC0IolWxXJ --target http://localhost:12000/github &
```

### Test the Integration

Push a commit to trigger the pipeline:

```bash
git commit --allow-empty -m "Test Argo Events trigger"
git push origin master

# Watch pipeline runs
kubectl get pipelineruns -n tekton-builds -w
```

## How It Works

1. **GitHub Push** → You push code to the `master` branch
2. **Smee.io** → GitHub sends webhook to smee.io channel, which forwards to localhost:12000
3. **Port-forward** → Routes localhost:12000 to the Argo Events webhook service
4. **EventSource** → Receives the webhook and publishes it to the JetStream EventBus
5. **Sensor** → Listens for push events and triggers a Tekton PipelineRun
6. **Tekton** → Clones repo, builds Docker image, pushes to Harbor, updates deployment tag

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
