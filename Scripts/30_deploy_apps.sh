#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 30_deploy_apps — deploy chell-test (the fat-image app) into $NS_SCI.
# Pulls nicolaka/netshoot from a public registry; no local build. Idempotent.

preflight

MANIFEST_NS="${REPO_ROOT}/manifests/00-namespaces.yaml"
MANIFEST_APP="${REPO_ROOT}/manifests/aperture-sci/chell-test.yaml"

info "Creating demo namespaces"
render_manifest "$MANIFEST_NS" NS_SCI NS_LABS | kube apply -f -

info "Deploying chell-test -> ${NS_SCI}  (image: ${CLEAN_APP_IMAGE})"
render_manifest "$MANIFEST_APP" \
  NS_SCI CLEAN_APP_IMAGE IMAGE_PULL_POLICY BASELINE_TARGET_URL BASELINE_INTERVAL_SECONDS \
  | kube apply -f -

wait_for_rollout deploy/chell-test "$NS_SCI" 180s

cat >&2 <<EOF

$(info "chell-test is running.")
  Watch the baseline loop:
    ${KUBECTL} ${KUBE_CONTEXT:+--context ${KUBE_CONTEXT} }logs -f -n ${NS_SCI} deploy/chell-test

  In the NeuVector console: Policy -> Groups should soon list
    nv.chell-test.${NS_SCI}   (starts in Discover — let it learn a few minutes)

  Next: Scripts/31_deploy_distroless.sh
EOF
