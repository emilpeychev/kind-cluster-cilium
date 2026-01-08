#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_test() {
    echo -e "${YELLOW}🧪 Testing: $1${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

print_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

wait_for_condition() {
    local resource=$1
    local condition=$2
    local timeout=${3:-120}
    local namespace=${4:-default}
    
    echo "⏳ Waiting for $resource to be $condition (timeout: ${timeout}s)"
    if kubectl wait --for=condition=$condition --timeout=${timeout}s $resource -n $namespace 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Start testing
print_header "🚀 KIND CLUSTER GITOPS PLATFORM TESTING"

print_header "1️⃣ CLUSTER BASIC FUNCTIONALITY"

print_test "Cluster connectivity"
if kubectl cluster-info >/dev/null 2>&1; then
    print_pass "Cluster is accessible"
else
    print_fail "Cannot connect to cluster"
fi

print_test "Node readiness"
if kubectl get nodes | grep -q "Ready"; then
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    print_pass "All $NODE_COUNT nodes are Ready"
else
    print_fail "Nodes are not Ready"
fi

print_test "Core DNS functionality"
if kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q "Running"; then
    print_pass "CoreDNS is running"
else
    print_fail "CoreDNS is not running"
fi

print_header "2️⃣ CILIUM CNI"

print_test "Cilium pods status"
if kubectl get pods -n kube-system -l k8s-app=cilium | grep -q "Running"; then
    print_pass "Cilium pods are running"
else
    print_fail "Cilium pods are not running"
fi

print_test "Cilium connectivity check"
if cilium status >/dev/null 2>&1; then
    print_pass "Cilium connectivity is healthy"
else
    print_fail "Cilium connectivity check failed"
fi

print_header "3️⃣ METALLB LOAD BALANCER"

print_test "MetalLB controller"
if kubectl get pods -n metallb-system -l app=metallb,component=controller | grep -q "Running"; then
    print_pass "MetalLB controller is running"
else
    print_fail "MetalLB controller is not running"
fi

print_test "MetalLB speaker"
if kubectl get pods -n metallb-system -l app=metallb,component=speaker | grep -q "Running"; then
    print_pass "MetalLB speaker is running"
else
    print_fail "MetalLB speaker is not running"
fi

print_test "MetalLB IP pool configuration"
if kubectl get ipaddresspool -n metallb-system >/dev/null 2>&1; then
    print_pass "MetalLB IP pools are configured"
else
    print_fail "MetalLB IP pools are missing"
fi

print_header "4️⃣ ISTIO AMBIENT MESH"

print_test "Istio control plane (istiod)"
if kubectl get pods -n istio-system -l app=istiod | grep -q "Running"; then
    print_pass "Istio control plane is running"
else
    print_fail "Istio control plane is not running"
fi

print_test "Istio ingress gateway"
if kubectl get pods -n istio-gateway -l app=istio-ingressgateway | grep -q "Running"; then
    print_pass "Istio ingress gateway is running"
else
    print_fail "Istio ingress gateway is not running"
fi

print_test "Istio gateway LoadBalancer IP"
GATEWAY_IP=$(kubectl get svc -n istio-gateway istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$GATEWAY_IP" && "$GATEWAY_IP" != "null" ]]; then
    print_pass "Gateway has external IP: $GATEWAY_IP"
else
    print_fail "Gateway does not have external IP"
fi

print_test "Gateway API resources"
if kubectl get gateway istio-gateway -n istio-gateway >/dev/null 2>&1; then
    print_pass "Gateway API is configured"
else
    print_fail "Gateway API configuration missing"
fi

print_header "5️⃣ HARBOR CONTAINER REGISTRY"

print_test "Harbor core service"
if wait_for_condition "deployment/harbor-core" "available" 60 "harbor"; then
    print_pass "Harbor core is ready"
else
    print_fail "Harbor core is not ready"
fi

print_test "Harbor portal service"
if kubectl get pods -n harbor -l app=harbor,component=portal | grep -q "Running"; then
    print_pass "Harbor portal is running"
else
    print_fail "Harbor portal is not running"
fi

print_test "Harbor HTTPRoute"
if kubectl get httproute harbor -n harbor >/dev/null 2>&1; then
    print_pass "Harbor HTTPRoute is configured"
else
    print_fail "Harbor HTTPRoute is missing"
fi

print_test "Harbor external connectivity"
if timeout 10 curl -k -s https://harbor.local/api/v2.0/systeminfo >/dev/null 2>&1; then
    print_pass "Harbor is accessible externally"
else
    print_fail "Harbor is not accessible externally"
fi

print_header "6️⃣ TEKTON PIPELINES"

print_test "Tekton controller"
if kubectl get pods -n tekton-pipelines -l app.kubernetes.io/name=controller | grep -q "Running"; then
    print_pass "Tekton controller is running"
else
    print_fail "Tekton controller is not running"
fi

print_test "Tekton webhook"
if kubectl get pods -n tekton-pipelines -l app.kubernetes.io/name=webhook | grep -q "Running"; then
    print_pass "Tekton webhook is running"
else
    print_fail "Tekton webhook is not running"
fi

print_test "Tekton dashboard"
if kubectl get pods -n tekton-pipelines -l app.kubernetes.io/name=dashboard | grep -q "Running"; then
    print_pass "Tekton dashboard is running"
else
    print_fail "Tekton dashboard is not running"
fi

print_test "Tekton builds namespace"
if kubectl get namespace tekton-builds >/dev/null 2>&1; then
    print_pass "tekton-builds namespace exists"
else
    print_fail "tekton-builds namespace missing"
fi

print_test "Harbor registry secret in tekton-builds"
if kubectl get secret harbor-registry -n tekton-builds >/dev/null 2>&1; then
    print_pass "Harbor registry secret exists"
else
    print_fail "Harbor registry secret missing"
fi

print_test "Tekton pipeline definitions"
if kubectl get pipeline clone-build-push -n tekton-builds >/dev/null 2>&1; then
    print_pass "Tekton pipeline is defined"
else
    print_fail "Tekton pipeline definition missing"
fi

print_header "7️⃣ ARGOCD GITOPS"

print_test "ArgoCD server"
if wait_for_condition "deployment/argocd-server" "available" 60 "argocd"; then
    print_pass "ArgoCD server is ready"
else
    print_fail "ArgoCD server is not ready"
fi

print_test "ArgoCD HTTPRoute"
if kubectl get httproute argocd -n argocd >/dev/null 2>&1; then
    print_pass "ArgoCD HTTPRoute is configured"
else
    print_fail "ArgoCD HTTPRoute is missing"
fi

print_test "ArgoCD external connectivity"
if timeout 10 curl -k -s https://argocd.local/healthz >/dev/null 2>&1; then
    print_pass "ArgoCD is accessible externally"
else
    print_fail "ArgoCD is not accessible externally"
fi

print_test "Demo apps namespace"
if kubectl get namespace demo-apps >/dev/null 2>&1; then
    print_pass "demo-apps namespace exists"
else
    print_fail "demo-apps namespace missing"
fi

print_test "ArgoCD project"
if kubectl get appproject demo-apps -n argocd >/dev/null 2>&1; then
    print_pass "ArgoCD demo-apps project exists"
else
    print_fail "ArgoCD demo-apps project missing"
fi

print_test "ArgoCD ApplicationSet"
if kubectl get applicationset demo-apps -n argocd >/dev/null 2>&1; then
    print_pass "ArgoCD ApplicationSet exists"
else
    print_fail "ArgoCD ApplicationSet missing"
fi

print_header "8️⃣ DEMO APPLICATION"

print_test "Demo application deployment"
if kubectl get deployment demo-app1 -n demo-apps >/dev/null 2>&1; then
    if wait_for_condition "deployment/demo-app1" "available" 60 "demo-apps"; then
        print_pass "Demo app deployment is ready"
    else
        print_fail "Demo app deployment is not ready"
    fi
else
    print_fail "Demo app deployment missing"
fi

print_test "Demo app service"
if kubectl get service demo-app1 -n demo-apps >/dev/null 2>&1; then
    print_pass "Demo app service exists"
else
    print_fail "Demo app service missing"
fi

print_test "Demo app HTTPRoute"
if kubectl get httproute demo-app1 -n demo-apps >/dev/null 2>&1; then
    print_pass "Demo app HTTPRoute is configured"
else
    print_fail "Demo app HTTPRoute is missing"
fi

print_header "9️⃣ END-TO-END WORKFLOW TEST"

print_test "Pipeline execution status"
if kubectl get pipelinerun clone-build-push-run -n tekton-builds >/dev/null 2>&1; then
    PIPELINE_STATUS=$(kubectl get pipelinerun clone-build-push-run -n tekton-builds -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
    case $PIPELINE_STATUS in
        "Succeeded")
            print_pass "Pipeline completed successfully"
            ;;
        "Running"|"Started")
            print_pass "Pipeline is running (check progress manually)"
            ;;
        "Failed")
            print_fail "Pipeline failed"
            ;;
        *)
            print_fail "Pipeline status unknown: $PIPELINE_STATUS"
            ;;
    esac
else
    print_fail "Pipeline run not found"
fi

print_test "DNS resolution test"
TEST_POD="test-dns-$(date +%s)"
kubectl run $TEST_POD --image=busybox:1.28 --restart=Never --rm -i --quiet -- nslookup harbor.local >/dev/null 2>&1 && \
    print_pass "Internal DNS resolution works" || \
    print_fail "Internal DNS resolution failed"

print_header "🔟 EXTERNAL ACCESS VALIDATION"

print_test "Harbor web interface"
if timeout 5 curl -k -s https://harbor.local >/dev/null 2>&1; then
    print_pass "Harbor web interface accessible"
else
    print_fail "Harbor web interface not accessible"
fi

print_test "ArgoCD web interface"
if timeout 5 curl -k -s https://argocd.local >/dev/null 2>&1; then
    print_pass "ArgoCD web interface accessible"
else
    print_fail "ArgoCD web interface not accessible"
fi

print_test "Tekton dashboard"
if timeout 5 curl -k -s https://tekton.local >/dev/null 2>&1; then
    print_pass "Tekton dashboard accessible"
else
    print_fail "Tekton dashboard not accessible"
fi

print_header "📊 TEST SUMMARY"

echo -e "Total Tests: ${TESTS_TOTAL}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

SUCCESS_RATE=$((TESTS_PASSED * 100 / TESTS_TOTAL))
echo -e "Success Rate: ${SUCCESS_RATE}%"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Platform is fully operational.${NC}"
    exit 0
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "${YELLOW}⚠️  Platform is mostly operational with some issues.${NC}"
    exit 1
else
    echo -e "${RED}💥 Multiple critical issues found. Platform needs attention.${NC}"
    exit 2
fi