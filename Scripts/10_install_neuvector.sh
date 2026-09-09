#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 10_install_neuvector — helm upgrade --install NeuVector (SUSE Security) into
# the $NEUVECTOR_NAMESPACE namespace. Idempotent: re-running reconciles the
# release. The one platform-specific part is the CRI runtime flags, driven by
# $NEUVECTOR_CRI_RUNTIME / $NEUVECTOR_CONTAINERD_SOCK from env.sh.

need helm
preflight

RELEASE="neuvector"
CHART="neuvector/core"

# ── Repo ────────────────────────────────────────────────────────────────────
if ! helm repo list 2>/dev/null | awk '{print $2}' | grep -qxF "$NEUVECTOR_HELM_REPO"; then
  info "Adding helm repo: ${NEUVECTOR_HELM_REPO}"
  helm repo add neuvector "$NEUVECTOR_HELM_REPO"
fi
info "Updating helm repos"
helm repo update neuvector >/dev/null

# ── Version ────────────────────────────────────────────────────────────────
version_args=()
if [[ -n "$NEUVECTOR_CHART_VERSION" ]]; then
  version_args=(--version "$NEUVECTOR_CHART_VERSION")
  info "Chart version pinned: ${NEUVECTOR_CHART_VERSION}"
else
  latest="$(helm search repo "$CHART" --versions 2>/dev/null | awk 'NR==2 {print $2}')"
  warn "NEUVECTOR_CHART_VERSION not set — using newest available: ${latest:-unknown}. Pin it in env.sh for reproducibility."
fi

# ── CRI runtime flags (the platform-specific bit) ──────────────────────────
cri_args=()
case "$NEUVECTOR_CRI_RUNTIME" in
  k3s)
    cri_args=(--set k3s.enabled=true --set "k3s.runtimePath=${NEUVECTOR_CONTAINERD_SOCK}")
    ;;
  containerd)
    cri_args=(--set containerd.enabled=true --set "containerd.path=${NEUVECTOR_CONTAINERD_SOCK}")
    ;;
  crio)
    cri_args=(--set crio.enabled=true --set "crio.path=${NEUVECTOR_CONTAINERD_SOCK}")
    ;;
  docker)
    cri_args=(--set docker.enabled=true)
    ;;
  *)
    die "NEUVECTOR_CRI_RUNTIME='${NEUVECTOR_CRI_RUNTIME}' unsupported. Expected: k3s | containerd | docker | crio"
    ;;
esac
info "CRI runtime: ${NEUVECTOR_CRI_RUNTIME}  (${cri_args[*]})"

# ── Install / upgrade ─────────────────────────────────────────────────────
info "helm upgrade --install ${RELEASE} ${CHART} -> namespace ${NEUVECTOR_NAMESPACE}"
helm_cmd upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NEUVECTOR_NAMESPACE" --create-namespace \
  "${version_args[@]}" \
  --set controller.replicas=1 \
  --set manager.svc.type=ClusterIP \
  --set cve.scanner.replicas=1 \
  "${cri_args[@]}" \
  --wait --timeout 10m

# ── Wait for the control plane ───────────────────────────────────────────
info "Waiting for the NeuVector control plane"
kube -n "$NEUVECTOR_NAMESPACE" rollout status deploy/neuvector-controller-pod --timeout 300s
kube -n "$NEUVECTOR_NAMESPACE" rollout status deploy/neuvector-manager-pod --timeout 300s
kube -n "$NEUVECTOR_NAMESPACE" rollout status ds/neuvector-enforcer-pod --timeout 300s || \
  warn "Enforcer DaemonSet not fully ready yet — check: kube -n ${NEUVECTOR_NAMESPACE} get pods"

kube -n "$NEUVECTOR_NAMESPACE" get pods

if [[ "$NEUVECTOR_ADMIN_PASSWORD" != "admin" ]]; then
  warn "NEUVECTOR_ADMIN_PASSWORD is set but this script does not apply it. Log in as admin/admin and change the password on first login."
fi

info "NeuVector installed — next: Scripts/20_expose_console.sh"
