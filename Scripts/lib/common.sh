# shellcheck shell=bash
#
# common.sh — shared helpers for the Aperture Container Enrichment Center demo.
#
# Source this as the first line of every script in Scripts/:
#
#     #!/usr/bin/env bash
#     set -euo pipefail
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
#
# It loads env.sh, fills in defaults, and exposes:
#   kube ...............  kubectl wrapper that honours $KUBE_CONTEXT
#   helm_cmd ..........  helm wrapper that honours $KUBE_CONTEXT
#   need <cmd> .........  assert a command is on PATH
#   build_image <img> <ctx> [args...] ...  build for the current $PLATFORM
#   push_image <img> ..............  make a built image visible to the cluster
#   render_manifest <file> [VAR...] ...  expand ${VAR} refs from env.sh
#   ensure_namespace <ns>
#   wait_for_rollout <kind/name> <ns> [timeout]
#   preflight ..........  assert the cluster is reachable
#   log / info / warn / err / die

# Guard against double-sourcing.
[[ -n "${_ACEC_COMMON_SH:-}" ]] && return 0
_ACEC_COMMON_SH=1

# ── Paths ────────────────────────────────────────────────────────────────────
# Resolve the repo root from this file's location, so scripts work no matter
# what the caller's working directory is.
_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_common_dir}/../.." && pwd)"
export REPO_ROOT

# ── Logging ──────────────────────────────────────────────────────────────────
if [[ -t 2 ]]; then
  _c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_yellow=$'\033[33m'
  _c_blue=$'\033[34m'; _c_green=$'\033[32m'
else
  _c_reset=''; _c_red=''; _c_yellow=''; _c_blue=''; _c_green=''
fi

log()  { printf '%s[ACEC]%s %s\n'       "$_c_blue"   "$_c_reset" "$*" >&2; }
info() { printf '%s[ACEC]%s %s\n'       "$_c_green"  "$_c_reset" "$*" >&2; }
warn() { printf '%s[ACEC:WARN]%s %s\n'  "$_c_yellow" "$_c_reset" "$*" >&2; }
err()  { printf '%s[ACEC:ERROR]%s %s\n' "$_c_red"    "$_c_reset" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── Environment ──────────────────────────────────────────────────────────────
ENV_FILE="${ACEC_ENV_FILE:-${REPO_ROOT}/env.sh}"
if [[ ! -f "$ENV_FILE" ]]; then
  die "No env.sh found at ${ENV_FILE}
     Copy the template and edit it for your environment:
       cp \"${REPO_ROOT}/Files/env.sh.example\" \"${REPO_ROOT}/env.sh\""
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# Defaults for anything env.sh left unset or blank, so `set -u` is safe below.
: "${PLATFORM:=generic}"
: "${KUBECTL:=kubectl}"
: "${KUBE_CONTEXT:=}"
: "${CONTAINER_TOOL:=docker}"
: "${CONTAINERD_NAMESPACE:=k8s.io}"
: "${REGISTRY:=}"
: "${IMAGE_PULL_POLICY:=IfNotPresent}"
: "${NEUVECTOR_NAMESPACE:=neuvector}"
: "${NEUVECTOR_HELM_REPO:=https://neuvector.github.io/neuvector-helm/}"
: "${NEUVECTOR_CHART_VERSION:=}"
: "${NEUVECTOR_CRI_RUNTIME:=k3s}"
: "${NEUVECTOR_CONTAINERD_SOCK:=/run/k3s/containerd/containerd.sock}"
: "${NEUVECTOR_CONSOLE_EXPOSE:=port-forward}"
: "${NEUVECTOR_CONSOLE_PORT:=8443}"
: "${NEUVECTOR_ADMIN_PASSWORD:=admin}"
: "${NS_SCI:=aperture-sci}"
: "${NS_LABS:=aperture-labs}"
: "${CLEAN_APP_IMAGE:=nicolaka/netshoot:latest}"
: "${DISTROLESS_APP_IMAGE:=wheatley-server:latest}"
: "${DEBUG_IMAGE:=busybox:1.36}"
: "${BASELINE_TARGET_URL:=https://www.fastly.com}"
: "${BASELINE_INTERVAL_SECONDS:=5}"
: "${EICAR_URL:=https://secure.eicar.org/eicar.com.txt}"
: "${DEMO_HOSTNAME:=}"

case "$PLATFORM" in
  rancher-desktop|k3s|k3d|kind|minikube|generic) : ;;
  *) die "Unknown PLATFORM '${PLATFORM}' in ${ENV_FILE}. Expected one of: rancher-desktop k3s k3d kind minikube generic" ;;
esac

# ── kubectl wrapper ──────────────────────────────────────────────────────────
# Always call `kube` instead of raw `kubectl` so $KUBE_CONTEXT is applied.
kube() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    "$KUBECTL" --context "$KUBE_CONTEXT" "$@"
  else
    "$KUBECTL" "$@"
  fi
}

# ── helm wrapper ─────────────────────────────────────────────────────────────
# Mirrors kube(): honours $KUBE_CONTEXT so helm targets the same cluster.
helm_cmd() {
  need helm
  if [[ -n "$KUBE_CONTEXT" ]]; then
    helm --kube-context "$KUBE_CONTEXT" "$@"
  else
    helm "$@"
  fi
}

# ── Manifest rendering ───────────────────────────────────────────────────────
# render_manifest <file> [VAR ...]
#   Print <file> with ${VAR} references expanded from the environment. Name the
#   VARs to restrict substitution to that safelist (so any other shell-ish
#   syntax in the manifest is left untouched); pass none to expand everything.
render_manifest() {
  local file="${1:-}"; shift || true
  [[ -f "$file" ]] || die "render_manifest: no such file: $file"
  need envsubst
  if [[ $# -gt 0 ]]; then
    local list="" v
    for v in "$@"; do list+="\${${v}} "; done
    # env.sh values are plain shell vars; envsubst only sees the environment, so
    # export the safelisted names in a subshell just for this call.
    ( for v in "$@"; do export "${v?}"; done; envsubst "$list" < "$file" )
  else
    envsubst < "$file"
  fi
}

# ── Assertions ───────────────────────────────────────────────────────────────
need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found on PATH: $1"
}

preflight() {
  need "$KUBECTL"
  if ! kube get nodes -o name >/dev/null 2>&1; then
    die "Cannot reach the cluster (context: ${KUBE_CONTEXT:-current-context}).
     Check that your cluster is running and KUBE_CONTEXT in env.sh is correct."
  fi
  local ctx; ctx="$(kube config current-context 2>/dev/null || echo '?')"
  info "Cluster reachable — platform=${PLATFORM} context=${KUBE_CONTEXT:-$ctx}"
}

# ── Namespaces & rollouts ────────────────────────────────────────────────────
ensure_namespace() {
  local ns="$1"
  if kube get namespace "$ns" >/dev/null 2>&1; then
    log "Namespace ${ns} already exists"
  else
    info "Creating namespace ${ns}"
    kube create namespace "$ns"
  fi
}

wait_for_rollout() {
  local target="$1" ns="$2" timeout="${3:-120s}"
  info "Waiting for ${target} in ${ns} (timeout ${timeout})"
  kube -n "$ns" rollout status "$target" --timeout "$timeout"
}

# ── Image build & delivery ───────────────────────────────────────────────────
# build_image <image-ref> <context-dir> [extra build args...]
#   Builds with $CONTAINER_TOOL. On Rancher Desktop / k3s with nerdctl the build
#   targets the k8s.io containerd namespace so the kubelet can see the result.
build_image() {
  local image="${1:-}" context="${2:-}"
  [[ -n "$image" && -n "$context" ]] || die "usage: build_image <image-ref> <context-dir> [build-args...]"
  shift 2 || true
  need "$CONTAINER_TOOL"

  local -a cmd=("$CONTAINER_TOOL")
  if [[ "$CONTAINER_TOOL" == "nerdctl" && ( "$PLATFORM" == "rancher-desktop" || "$PLATFORM" == "k3s" ) ]]; then
    cmd+=(--namespace "$CONTAINERD_NAMESPACE")
  fi
  cmd+=(build -t "$image")
  [[ $# -gt 0 ]] && cmd+=("$@")
  cmd+=("$context")

  info "Building ${image}"
  log  "  ${cmd[*]}"
  "${cmd[@]}"
}

# push_image <image-ref>
#   Makes a locally-built image available to the cluster.
#   - $REGISTRY set  -> push to the registry (works for every platform).
#   - otherwise      -> use the platform's local-load mechanism.
push_image() {
  local image="${1:-}"
  [[ -n "$image" ]] || die "usage: push_image <image-ref>"

  if [[ -n "$REGISTRY" ]]; then
    need "$CONTAINER_TOOL"
    info "Pushing ${image} to registry"
    "$CONTAINER_TOOL" push "$image"
    return
  fi

  case "$PLATFORM" in
    rancher-desktop|k3s)
      if [[ "$CONTAINER_TOOL" == "nerdctl" ]]; then
        # build_image already placed it in the k8s.io namespace; just verify.
        "$CONTAINER_TOOL" --namespace "$CONTAINERD_NAMESPACE" image inspect "$image" >/dev/null 2>&1 \
          || die "Image ${image} not in containerd namespace ${CONTAINERD_NAMESPACE}. Run build_image first."
        info "Image ${image} present in containerd namespace ${CONTAINERD_NAMESPACE}"
      else
        warn "PLATFORM=${PLATFORM} with CONTAINER_TOOL=${CONTAINER_TOOL}: assuming the dockerd engine already shares the image with the kubelet."
      fi
      ;;
    k3d)      need k3d;      info "Importing ${image} into k3d";      k3d image import "$image" ;;
    kind)     need kind;     info "Loading ${image} into kind";       kind load docker-image "$image" ;;
    minikube) need minikube; info "Loading ${image} into minikube";   minikube image load "$image" ;;
    generic)
      die "PLATFORM=generic needs REGISTRY set in env.sh so images can be pushed somewhere the cluster can pull them."
      ;;
  esac
}
