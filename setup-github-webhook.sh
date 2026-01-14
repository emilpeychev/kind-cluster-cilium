#!/usr/bin/env bash
set -euo pipefail

REPO="emilpeychev/kind-cluster-cilium"
WEBHOOK_SECRET="webhook-secret-123"

echo "================================================"
echo "GitHub Webhook Setup for Tekton Automation"
echo "================================================"
echo ""
echo "Repository: git@github.com:${REPO}.git"
echo ""

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "❌ ngrok is not installed"
    echo ""
    echo "Install ngrok:"
    echo "  Linux: snap install ngrok"
    echo "  macOS: brew install ngrok"
    echo "  Or download from: https://ngrok.com/download"
    echo ""
    exit 1
fi

# Check if webhook service is ready
echo "==> Checking if webhook service is ready..."
if ! kubectl get svc github-eventsource-svc -n argo-events &> /dev/null; then
    echo "❌ Webhook service not found. Run the setup script first."
    exit 1
fi

echo "✅ Webhook service is ready"
echo ""

# Start port-forward in background
echo "==> Starting port-forward to webhook service..."
kubectl port-forward -n argo-events svc/github-eventsource-svc 12000:12000 > /dev/null 2>&1 &
PF_PID=$!
echo "✅ Port-forward started (PID: $PF_PID)"
sleep 3

# Start ngrok
echo ""
echo "==> Starting ngrok tunnel..."
echo "⚠️  Press Ctrl+C to stop the tunnel when done"
echo ""

# Run ngrok and capture output
ngrok http 12000 --log=stdout 2>&1 | tee /tmp/ngrok.log &
NGROK_PID=$!

# Wait for ngrok to start and get the URL
sleep 5

# Get ngrok URL from API
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' 2>/dev/null || echo "")

if [[ -z "$NGROK_URL" ]]; then
    echo ""
    echo "⚠️  Could not auto-detect ngrok URL"
    echo "Please check ngrok web interface at: http://localhost:4040"
else
    # Ensure HTTPS
    NGROK_URL="${NGROK_URL/http:/https:}"
    
    echo ""
    echo "================================================"
    echo "✅ Ngrok tunnel is running!"
    echo "================================================"
    echo ""
    echo "Webhook URL: ${NGROK_URL}/push"
    echo "Web Interface: http://localhost:4040"
    echo ""
    echo "================================================"
    echo "Configure GitHub Webhook:"
    echo "================================================"
    echo ""
    echo "1. Go to: https://github.com/${REPO}/settings/hooks/new"
    echo ""
    echo "2. Fill in the form:"
    echo "   Payload URL: ${NGROK_URL}/push"
    echo "   Content type: application/json"
    echo "   Secret: ${WEBHOOK_SECRET}"
    echo "   SSL verification: Enable SSL verification"
    echo ""
    echo "3. Which events would you like to trigger this webhook?"
    echo "   ☑ Just the push event"
    echo ""
    echo "4. Click 'Add webhook'"
    echo ""
    echo "================================================"
    echo "Test the webhook:"
    echo "================================================"
    echo ""
    echo "# Push a commit to your repo"
    echo "git commit --allow-empty -m 'Test webhook trigger'"
    echo "git push origin master"
    echo ""
    echo "# Watch for triggered pipelines"
    echo "kubectl get pipelineruns -n tekton-builds -w"
    echo ""
    echo "================================================"
    echo ""
    echo "⚠️  Keep this terminal open to maintain the tunnel"
    echo "   Press Ctrl+C to stop"
    echo ""
fi

# Cleanup function
cleanup() {
    echo ""
    echo "==> Cleaning up..."
    kill $PF_PID 2>/dev/null || true
    kill $NGROK_PID 2>/dev/null || true
    echo "✅ Stopped port-forward and ngrok"
}

trap cleanup EXIT INT TERM

# Keep script running
wait $NGROK_PID
