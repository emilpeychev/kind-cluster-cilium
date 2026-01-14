#!/usr/bin/env bash
set -euo pipefail

echo "Testing Argo Events GitHub Webhook Integration"
echo "================================================"

# Test the webhook endpoint
echo ""
echo "1. Testing webhook endpoint (https://argo-workflows.local/push)..."
RESPONSE=$(curl -k -X POST https://argo-workflows.local/push \
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
  }' \
  -w "\nHTTP Status: %{http_code}\n" \
  2>/dev/null)

echo "$RESPONSE"

echo ""
echo "2. Checking EventSource logs..."
kubectl logs -n argo-events -l eventsource-name=github --tail=10

echo ""
echo "3. Checking Sensor logs..."
kubectl logs -n argo-events -l sensor-name=github-tekton-trigger --tail=10

echo ""
echo "4. Checking for triggered PipelineRuns..."
kubectl get pipelineruns -n tekton-builds --sort-by=.metadata.creationTimestamp | tail -5

echo ""
echo "================================================"
echo "If you see a new PipelineRun, the integration is working!"
echo "================================================"
