#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  echo "==> $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

check_host_dns() {
  local host="$1"

  if [[ "${SKIP_DNS_CHECK:-0}" == "1" ]]; then
    return 0
  fi

  if getent ahosts "$host" >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: DNS lookup failed for: $host" >&2
  echo "Fix host DNS (VPN/resolv.conf/docker DNS) or set SKIP_DNS_CHECK=1 to bypass." >&2
  exit 1
}

ensure_kind_network() {
  local subnet="$1"
  log "Ensuring Docker 'kind' network exists"
  if docker network inspect kind >/dev/null 2>&1; then
    log "Docker 'kind' network already exists"
  else
    docker network create kind --subnet "$subnet"
  fi
  docker network inspect kind | grep Subnet || true
}

ensure_kube_context() {
  local ctx="$1"
  if kubectl config get-contexts "$ctx" >/dev/null 2>&1; then
    kubectl config use-context "$ctx" >/dev/null
  fi
}

kapply() {
  kubectl apply "$@"
}
