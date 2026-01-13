#!/usr/bin/env bash
set -euo pipefail
# Master setup script with component selection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${SCRIPT_DIR}/z-setup-scr/setup-scripts"
CONFIG_DIR="${SCRIPT_DIR}/z-setup-scr/config-scripts"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Options:
  all       Run full setup (all components)
  cluster   Part 1: Cluster, Gateway, TLS (install + config)
  harbor    Part 2: Harbor registry (install + config)
  tekton    Part 3: Tekton pipelines (install + config)
  argocd    Part 4: ArgoCD (install + config)
  install   Run all install scripts only
  config    Run all config scripts only
  help      Show this help message

Examples:
  $(basename "$0") all       # Full setup
  $(basename "$0") cluster   # Only cluster/gateway/tls
  $(basename "$0") install   # All installs, no configs

EOF
  exit 0
}

run_cluster() {
  echo "==> Running Part 1: Cluster, Gateway, TLS"
  "${SETUP_DIR}/01-cluster-gateway-tls-install.sh"
  "${CONFIG_DIR}/01-cluster-gateway-tls-config.sh"
}

run_harbor() {
  echo "==> Running Part 2: Harbor"
  "${SETUP_DIR}/02-harbor-install.sh"
  "${CONFIG_DIR}/02-harbor-config.sh"
}

run_tekton() {
  echo "==> Running Part 3: Tekton"
  "${SETUP_DIR}/03-tekton-install.sh"
  "${CONFIG_DIR}/03-tekton-config.sh"
}

run_argocd() {
  echo "==> Running Part 4: ArgoCD"
  "${SETUP_DIR}/04-argocd-install.sh"
  "${CONFIG_DIR}/04-argocd-config.sh"
}

run_all_installs() {
  echo "==> Running all install scripts..."
  "${SETUP_DIR}/01-cluster-gateway-tls-install.sh"
  "${SETUP_DIR}/02-harbor-install.sh"
  "${SETUP_DIR}/03-tekton-install.sh"
  "${SETUP_DIR}/04-argocd-install.sh"
  echo "✔ All install scripts completed"
  echo "Now run: $(basename "$0") config"
}

run_all_configs() {
  echo "==> Running all config scripts..."
  "${CONFIG_DIR}/01-cluster-gateway-tls-config.sh"
  "${CONFIG_DIR}/02-harbor-config.sh"
  "${CONFIG_DIR}/03-tekton-config.sh"
  "${CONFIG_DIR}/04-argocd-config.sh"
  echo "✔ All config scripts completed"
}

run_all() {
  echo "================================================"
  echo "Full Cluster Setup - Kind + Cilium + Istio"
  echo "================================================"
  run_cluster
  run_harbor
  run_tekton
  run_argocd
  echo "================================================"
  echo "✔ Full setup complete!"
  echo "================================================"
  echo "* ArgoCD: https://argocd.local"
  echo "* Harbor: https://harbor.local"
  echo "* Tekton: https://tekton.local"
  echo "* Demo App: https://demo-app1.local"
  echo "================================================"
}

# Main
case "${1:-help}" in
  all)
    run_all
    ;;
  cluster)
    run_cluster
    ;;
  harbor)
    run_harbor
    ;;
  tekton)
    run_tekton
    ;;
  argocd)
    run_argocd
    ;;
  install)
    run_all_installs
    ;;
  config)
    run_all_configs
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown option: $1"
    usage
    ;;
esac
