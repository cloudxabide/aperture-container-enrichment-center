#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 90_reset_demo — tear down the demo workloads (chell-test / wheatley) by
# deleting $NS_SCI and $NS_LABS. Idempotent: safe to re-run, safe if nothing
# is deployed yet.
#
#   --all, --with-neuvector   also helm-uninstall NeuVector and delete
#                             $NEUVECTOR_NAMESPACE
#   -y, --yes                 skip the confirmation prompt

WITH_NEUVECTOR=0
ASSUME_YES=0

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [--all|--with-neuvector] [-y|--yes]

  --all, --with-neuvector   also helm-uninstall the 'neuvector' release and
                             delete \$NEUVECTOR_NAMESPACE (${NEUVECTOR_NAMESPACE})
  -y, --yes                 skip the confirmation prompt
  -h, --help                show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all|--with-neuvector) WITH_NEUVECTOR=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
  shift
done

preflight

targets=("$NS_SCI" "$NS_LABS")
[[ "$WITH_NEUVECTOR" -eq 1 ]] && targets+=("$NEUVECTOR_NAMESPACE")

warn "This will delete namespace(s): ${targets[*]}"
[[ "$WITH_NEUVECTOR" -eq 1 ]] && warn "...and helm-uninstall the 'neuvector' release"

if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { info "Aborted — nothing deleted."; exit 0; }
fi

info "Deleting demo namespaces: ${NS_SCI} ${NS_LABS}"
kube delete namespace "$NS_SCI" "$NS_LABS" --ignore-not-found

if [[ "$WITH_NEUVECTOR" -eq 1 ]]; then
  if helm_cmd status neuvector -n "$NEUVECTOR_NAMESPACE" >/dev/null 2>&1; then
    info "helm uninstall neuvector -> ${NEUVECTOR_NAMESPACE}"
    helm_cmd uninstall neuvector -n "$NEUVECTOR_NAMESPACE"
  else
    log "No 'neuvector' helm release found in ${NEUVECTOR_NAMESPACE} — skipping helm uninstall"
  fi
  info "Deleting namespace ${NEUVECTOR_NAMESPACE}"
  kube delete namespace "$NEUVECTOR_NAMESPACE" --ignore-not-found
fi

info "Reset complete."
if [[ "$WITH_NEUVECTOR" -ne 1 ]]; then
  info "NeuVector left running in ${NEUVECTOR_NAMESPACE}. Re-run with --all to remove it too."
  info "Next: Scripts/30_deploy_apps.sh / Scripts/31_deploy_distroless.sh to redeploy the demo workloads."
else
  info "Next: Scripts/10_install_neuvector.sh to reinstall from scratch."
fi
