#!/usr/bin/env bash
set -euo pipefail
#
# setup.sh - Main menu for Kind cluster setup
#
# Usage:
#   ./setup.sh           # Interactive menu
#   ./setup.sh all       # Run all steps
#   ./setup.sh 1         # Run step 1 only
#   ./setup.sh 1-5       # Run steps 1 through 5
#   ./setup.sh 6 7 8     # Run steps 6, 7, and 8
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR/install-kind-cluster"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║       Kind Cluster Setup - Cilium + Istio + GitOps             ║"
  echo "╠════════════════════════════════════════════════════════════════╣"
  echo "║  1) Kind Cluster      7) Tekton Pipelines                      ║"
  echo "║  2) MetalLB           8) ArgoCD                                ║"
  echo "║  3) Cilium CNI        9) Argo Events + Smee                    ║"
  echo "║  4) Istio Ambient    10) Argo Workflows                        ║"
  echo "║  5) TLS + CoreDNS    11) Deploy Apps (HTTPBin)                 ║"
  echo "║  6) Harbor Registry  12) Observability (Kiali)                 ║"
  echo "╠════════════════════════════════════════════════════════════════╣"
  echo "║  all) Run all steps    delete) Delete cluster                  ║"
  echo "║  q) Quit                                                       ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

run_step() {
  local step="$1"
  local script=""
  
  case "$step" in
    1)  script="01-kind-cluster.sh" ;;
    2)  script="02-metallb.sh" ;;
    3)  script="03-cilium.sh" ;;
    4)  script="04-istio.sh" ;;
    5)  script="05-tls-certs.sh" ;;
    6)  script="06-harbor.sh" ;;
    7)  script="07-tekton.sh" ;;
    8)  script="08-argocd.sh" ;;
    9)  script="09-argo-events.sh" ;;
    10) script="10-argo-workflows.sh" ;;
    11) script="11-deploy-apps.sh" ;;
    12) script="12-kiali-setup.sh" ;;
    *)
      echo -e "${RED}Invalid step: $step${NC}" >&2
      return 1
      ;;
  esac
  
  if [[ -f "$INSTALL_DIR/$script" ]]; then
    echo -e "${GREEN}▶ Running step $step: $script${NC}"
    bash "$INSTALL_DIR/$script"
    echo -e "${GREEN}✔ Step $step completed${NC}"
    echo ""
  else
    echo -e "${RED}Script not found: $INSTALL_DIR/$script${NC}" >&2
    return 1
  fi
}

run_all() {
  echo -e "${YELLOW}Running all steps...${NC}"
  for i in {1..12}; do
    run_step "$i"
  done
  print_summary
}

run_range() {
  local range="$1"
  local start="${range%-*}"
  local end="${range#*-}"
  
  for ((i=start; i<=end; i++)); do
    run_step "$i"
  done
}

delete_cluster() {
  echo -e "${YELLOW}Deleting Kind cluster...${NC}"
  kind delete cluster --name test-cluster-1 || true
  echo -e "${GREEN}Cluster deleted${NC}"
}

print_summary() {
  echo -e "${GREEN}"
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                    Setup Complete!                             ║"
  echo "╠════════════════════════════════════════════════════════════════╣"
  echo "║  ArgoCD:         https://argocd.local                          ║"
  echo "║  Harbor:         https://harbor.local                          ║"
  echo "║  Tekton:         https://tekton.local                          ║"
  echo "║  Argo Workflows: https://workflows.local                       ║"
  echo "║  Webhooks:       https://webhooks.local                        ║"
  echo "║  Demo App:       https://demo-app1.local                       ║"
  echo "║  HTTPBin API:    https://httpbin.local                         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
  echo "Smee webhook forwarding: https://smee.io/1iIhi0YC0IolWxXJ"
  echo "ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  
  echo "** Note: Smee must be running to receive webhooks. Starting Smee... **"
  pkill -f smee
  smee --url https://smee.io/1iIhi0YC0IolWxXJ --target http://localhost:12000/github &
  echo "Smee is running in the background to forward webhooks."
}



# Main
if [[ $# -eq 0 ]]; then
  # Interactive menu
  while true; do
    print_banner
    read -rp "Select option: " choice
    
    case "$choice" in
      [1-9]|10|11|12)
        run_step "$choice"
        ;;
      all|a)
        run_all
        ;;
      delete|d)
        delete_cluster
        ;;
      q|quit|exit)
        echo "Goodbye!"
        exit 0
        ;;
      *-*)
        run_range "$choice"
        ;;
      *)
        echo -e "${RED}Invalid option: $choice${NC}"
        ;;
    esac
    
    echo ""
    read -rp "Press Enter to continue..."
  done
else
  # Command line arguments
  case "$1" in
    all|a)
      run_all
      ;;
    delete|d)
      delete_cluster
      ;;
    *-*)
      run_range "$1"
      ;;
    *)
      # Run specific steps
      for arg in "$@"; do
        run_step "$arg"
      done
      ;;
  esac
fi
