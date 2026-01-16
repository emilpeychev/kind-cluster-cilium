#!/usr/bin/env bash
set -euo pipefail

echo "================================================"
echo "GitHub + Tekton Integration with Argo Events"
echo "================================================"

# Prompt for GitHub credentials
read -p "Enter your GitHub Personal Access Token (or press Enter to skip): " GITHUB_TOKEN
read -p "Enter your GitHub Webhook Secret (or press Enter to use default): " WEBHOOK_SECRET

WEBHOOK_SECRET=${WEBHOOK_SECRET:-"my-webhook-secret-$(date +%s)"}

echo ""
echo "==> Step 1: Creating RBAC for Argo Events sensors"
kubectl apply -f ArgoDC-Events/rbac.yaml

echo ""
echo "==> Step 2: Creating GitHub credentials secrets"

if [[ -n "$GITHUB_TOKEN" ]]; then
  kubectl create secret generic github-access-token \
    --from-literal=token="$GITHUB_TOKEN" \
    -n argo-events \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ GitHub access token configured"
else
  echo "⚠ Skipping GitHub access token (webhook validation will be disabled)"
  # Create a dummy secret to prevent errors
  kubectl create secret generic github-access-token \
    --from-literal=token="dummy" \
    -n argo-events \
    --dry-run=client -o yaml | kubectl apply -f -
fi

kubectl create secret generic github-webhook-secret \
  --from-literal=token="$WEBHOOK_SECRET" \
  -n argo-events \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ GitHub webhook secret configured"

echo ""
echo "==> Step 3: Deploying GitHub EventSource"
kubectl apply -f ArgoDC-Events/github-eventsource.yaml

echo ""
echo "==> Step 4: Waiting for EventSource to be ready"
sleep 5
kubectl wait --for=condition=Ready pod -l eventsource-name=github -n argo-events --timeout=120s

echo ""
echo "==> Step 5: Deploying GitHub-Tekton Sensor"
kubectl apply -f ArgoDC-Events/github-tekton-sensor.yaml

echo ""
echo "==> Step 6: Waiting for Sensor to be ready"
sleep 5
kubectl wait --for=condition=Ready pod -l sensor-name=github-tekton-trigger -n argo-events --timeout=120s

# Get the webhook service details
WEBHOOK_PORT=$(kubectl get svc -n argo-events -l eventsource-name=github -o jsonpath='{.items[0].spec.ports[0].port}')
WEBHOOK_SERVICE=$(kubectl get svc -n argo-events -l eventsource-name=github -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "================================================"
echo "✅ GitHub + Tekton integration configured!"
echo "================================================"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Expose the webhook endpoint (choose one):"
echo ""
echo "   Option A: Port-forward (for local testing)"
echo "   kubectl port-forward -n argo-events svc/$WEBHOOK_SERVICE 12000:$WEBHOOK_PORT"
echo "   Then use: http://localhost:12000/push"
echo ""
echo "   Option B: Use ngrok or similar tunnel service"
echo "   kubectl port-forward -n argo-events svc/$WEBHOOK_SERVICE 12000:$WEBHOOK_PORT &"
echo "   ngrok http 12000"
echo ""
echo "   Option C: Create an HTTPRoute (if you have a public gateway)"
echo ""
echo "2. Configure GitHub webhook:"
echo "   - Go to: https://github.com/emilpeychev/kind-cluster-cilium/settings/hooks"
echo "   - Click 'Add webhook'"
echo "   - Payload URL: <your-webhook-url>/push"
echo "   - Content type: application/json"
echo "   - Secret: $WEBHOOK_SECRET"
echo "   - Events: Just the push event"
echo "   - Active: ✓"
echo ""
echo "3. Test by pushing to your repository:"
echo "   git commit --allow-empty -m 'Trigger Tekton pipeline'"
echo "   git push origin master"
echo ""
echo "4. Watch for triggered pipeline runs:"
echo "   kubectl get pipelineruns -n tekton-builds -w"
echo ""
echo "================================================"
