#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 31_deploy_distroless — build the wheatley image, make it visible to the
# cluster, and deploy it into $NS_LABS. Idempotent.
#
#   REGISTRY set   -> build + push to the registry
#   REGISTRY unset -> build + load via the platform's local mechanism
#                     (see build_image / push_image in lib/common.sh)

preflight

APP_DIR="${REPO_ROOT}/apps/wheatley"
MANIFEST_NS="${REPO_ROOT}/manifests/00-namespaces.yaml"
MANIFEST_APP="${REPO_ROOT}/manifests/aperture-labs/wheatley.yaml"

[[ -f "${APP_DIR}/Dockerfile" ]] || die "Missing ${APP_DIR}/Dockerfile"

info "Building wheatley image: ${DISTROLESS_APP_IMAGE}"
build_image "$DISTROLESS_APP_IMAGE" "$APP_DIR"

info "Making ${DISTROLESS_APP_IMAGE} available to the cluster (PLATFORM=${PLATFORM}, REGISTRY=${REGISTRY:-<none>})"
push_image "$DISTROLESS_APP_IMAGE"

info "Creating demo namespaces"
render_manifest "$MANIFEST_NS" NS_SCI NS_LABS | kube apply -f -

info "Deploying wheatley -> ${NS_LABS}"
render_manifest "$MANIFEST_APP" \
  NS_LABS DISTROLESS_APP_IMAGE IMAGE_PULL_POLICY \
  | kube apply -f -

wait_for_rollout deploy/wheatley "$NS_LABS" 180s

cat >&2 <<EOF

$(info "wheatley is running.")
  Smoke test:
    ${KUBECTL} ${KUBE_CONTEXT:+--context ${KUBE_CONTEXT} }port-forward -n ${NS_LABS} svc/wheatley 8080:8080 &
    curl localhost:8080/          # -> the Portal-flavoured banner
    curl localhost:8080/healthz   # -> OK

  In the NeuVector console: Policy -> Groups should soon list
    nv.wheatley.${NS_LABS}   (starts in Discover — let it learn a few minutes)

  Next: run the walkthroughs in docs/ (Security_Demo.md, Security_Demo_Distroless.md)
EOF
