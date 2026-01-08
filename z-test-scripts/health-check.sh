#!/usr/bin/env bash
set -euo pipefail

# Quick health check script for monitoring
echo "🔍 PLATFORM HEALTH CHECK"
echo "=========================="

# Check critical services
echo "📊 Critical Services Status:"
echo "----------------------------"

# Cluster
kubectl get nodes --no-headers | awk '{print "🖥️  Node " $1 ": " $2}'

# Gateway IP
GATEWAY_IP=$(kubectl get svc -n istio-gateway istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "N/A")
echo "🌐 Gateway IP: $GATEWAY_IP"

# Core deployments
echo ""
echo "🚀 Core Deployments:"
echo "--------------------"
kubectl get deployment -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.status.replicas" | grep -E "(harbor-core|argocd-server|tekton-pipelines|istio-ingressgateway|demo-app1)" || echo "⚠️  Some deployments not found"

# URLs
echo ""
echo "🔗 Platform URLs:"
echo "-----------------"
echo "• Harbor:    https://harbor.local"
echo "• ArgoCD:    https://argocd.local"
echo "• Tekton:    https://tekton.local"
echo "• Demo App:  https://demo-app1.local"

# Pipeline status
echo ""
echo "🔄 Latest Pipeline Status:"
echo "--------------------------"
kubectl get pipelinerun -n tekton-builds --sort-by=.metadata.creationTimestamp -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[0].reason,AGE:.metadata.creationTimestamp" | tail -3 || echo "No pipelines found"

# Quick connectivity test
echo ""
echo "⚡ Quick Connectivity Test:"
echo "---------------------------"
timeout 3 curl -k -s https://harbor.local >/dev/null 2>&1 && echo "✅ Harbor: OK" || echo "❌ Harbor: Failed"
timeout 3 curl -k -s https://argocd.local >/dev/null 2>&1 && echo "✅ ArgoCD: OK" || echo "❌ ArgoCD: Failed"
timeout 3 curl -k -s https://tekton.local >/dev/null 2>&1 && echo "✅ Tekton: OK" || echo "❌ Tekton: Failed"

echo ""
echo "Run './test-platform.sh' for comprehensive testing"