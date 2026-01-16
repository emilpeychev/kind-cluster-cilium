#!/usr/bin/env bash
set -euo pipefail

echo "==> Increasing file descriptor limits on Kind nodes..."
for node in test-cluster-1-control-plane test-cluster-1-worker test-cluster-1-worker2; do
  docker exec "$node" bash -c "echo 'fs.inotify.max_user_watches=524288' >> /etc/sysctl.conf"
  docker exec "$node" bash -c "echo 'fs.inotify.max_user_instances=512' >> /etc/sysctl.conf"
  docker exec "$node" sysctl -p || true
done

echo "==> Reinstalling Argo Events..."
helm uninstall argo-events -n argo-events --ignore-not-found || true
kubectl delete namespace argo-events --ignore-not-found=true
sleep 5

helm upgrade --install argo-events argo/argo-events \
  --version 2.4.19 \
  --create-namespace -n argo-events \
  -f ArgoDC-Events/values.yaml

echo "==> Waiting for Argo Events to be ready..."
kubectl wait --for=condition=available --timeout=180s \
  deployment/argo-events-controller-manager -n argo-events

echo "==> Creating EventBus..."
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
  namespace: argo-events
spec:
  nats:
    native:
      replicas: 1
      auth: none
EOF

echo "==> Waiting for EventBus to be ready..."
sleep 10
kubectl wait --for=condition=Ready pod -l controller=eventbus-controller -n argo-events --timeout=120s || true

echo "==> Deploying test EventSource (webhook)..."
kubectl apply -f ArgoDC-Events/test-webhook-eventsource.yaml

echo "==> Waiting for EventSource to be ready..."
sleep 5
kubectl wait --for=condition=Ready pod -l eventsource-name=webhook-test -n argo-events --timeout=120s

echo "==> Deploying test Sensor..."
kubectl apply -f ArgoDC-Events/test-sensor.yaml

echo "==> Waiting for Sensor to be ready..."
sleep 5
kubectl wait --for=condition=Ready pod -l sensor-name=webhook-sensor -n argo-events --timeout=120s

echo ""
echo "================================================"
echo "✅ Argo Events is ready for testing!"
echo "================================================"
echo ""
echo "To test the webhook, run:"
echo ""
echo "  # Port-forward the webhook service"
echo "  kubectl port-forward -n argo-events svc/webhook-test-eventsource-svc 12000:12000 &"
echo ""
echo "  # Send a test event"
echo "  curl -X POST http://localhost:12000/example -H 'Content-Type: application/json' -d '{\"message\": \"test\"}'"
echo ""
echo "  # Watch for the triggered pod"
echo "  kubectl get pods -n argo-events -w"
echo ""
echo "================================================"
