#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 00_preflight — verify the workstation and cluster are ready for the demo.
# Idempotent, read-only: safe to run any time.

info "Preflight for platform=${PLATFORM}"

# ── Required tools ───────────────────────────────────────────────────────────
need "$KUBECTL"
need helm
need "$CONTAINER_TOOL"
need envsubst

# ── Cluster reachable ───────────────────────────────────────────────────────
preflight   # from common.sh: asserts `kube get nodes` works, logs the context

# ── Node readiness ──────────────────────────────────────────────────────────
not_ready="$(kube get nodes \
  -o 'jsonpath={range .items[*]}{.metadata.name}={range .status.conditions[?(@.type=="Ready")]}{.status}{end} {end}' \
  2>/dev/null || true)"
if [[ "$not_ready" != *"=True"* ]]; then
  die "No node reports Ready=True:
     ${not_ready:-<none>}"
fi
info "Node(s) Ready: ${not_ready}"

node_count="$(kube get nodes -o name | wc -l | tr -d ' ')"
[[ "$node_count" == "1" ]] || warn "Cluster has ${node_count} nodes — this demo assumes a single node (one Enforcer, no cross-node segmentation)."

# ── containerd socket (only when NeuVector will use a host CRI socket) ───────
case "$NEUVECTOR_CRI_RUNTIME" in
  k3s|containerd|crio)
    if [[ -n "$NEUVECTOR_CONTAINERD_SOCK" ]]; then
      info "NeuVector will expect CRI socket ${NEUVECTOR_CONTAINERD_SOCK} on the node (runtime=${NEUVECTOR_CRI_RUNTIME})"
    fi
    ;;
  docker)
    info "NeuVector will use the docker runtime integration"
    ;;
  *)
    warn "NEUVECTOR_CRI_RUNTIME='${NEUVECTOR_CRI_RUNTIME}' is not one of: k3s containerd docker crio"
    ;;
esac

# ── Chart version pinned? ──────────────────────────────────────────────────
if [[ -z "$NEUVECTOR_CHART_VERSION" ]]; then
  warn "NEUVECTOR_CHART_VERSION is not pinned in env.sh — 10_install_neuvector.sh will use the newest chart in the repo. Pin it for reproducibility:"
  warn "  helm repo add neuvector \"$NEUVECTOR_HELM_REPO\" && helm repo update && helm search repo neuvector/core --versions | head"
fi

# ── Nothing from a previous run left behind (informational) ────────────────
for ns in "$NEUVECTOR_NAMESPACE" "$NS_SCI" "$NS_LABS"; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    warn "Namespace '${ns}' already exists — a previous run? (Scripts/90_reset_demo.sh clears the demo namespaces.)"
  fi
done

info "Preflight OK — next: Scripts/10_install_neuvector.sh"
