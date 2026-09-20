#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 40_attack_fat — Chamber 02 ("The Combustible Lemon"), scripted. Fires the
# same three kubectl exec attempts as docs/Security_Demo.md Part 3 (Steps
# 7-9) against deploy/chell-test, pausing $ATTACK_STEP_INTERVAL_SECONDS
# between each so the presenter can narrate / point at Security Events
# instead of typing live. Read-only against the cluster (no policy changes).
#
# Assumes the nv.chell-test.$NS_SCI group is already in Protect — this script
# doesn't check or set the policy mode, only fires the exec attempts.

preflight

kube get deploy/chell-test -n "$NS_SCI" >/dev/null 2>&1 || \
  die "deploy/chell-test not found in ${NS_SCI}. Run Scripts/30_deploy_apps.sh first."

info "Chamber 02 — firing the Combustible Lemon sequence against deploy/chell-test (${NS_SCI})"
info "Make sure nv.chell-test.${NS_SCI} is in Protect mode, then watch Notifications -> Security Events."

# run_attempt <label> <cmd...>
#   Runs <cmd> against the cluster, reporting its exit code without letting a
#   non-zero status (expected — every attempt here should be blocked) trip
#   `set -e`.
run_attempt() {
  local label="$1"; shift
  echo >&2
  info "${label}"
  log  "  $*"
  set +e
  "$@"
  local ec=$?
  set -e
  case "$ec" in
    0)   warn "  exit 0 — unexpected: this attempt should have been blocked" ;;
    137) info "  exit 137 (SIGKILLed by the Enforcer)" ;;
    *)   info "  exit ${ec}" ;;
  esac
}

sleep "$ATTACK_STEP_INTERVAL_SECONDS"
run_attempt "Step 7 — spawn a shell (expect: process profile violation, exit 137)" \
  kube exec -n "$NS_SCI" deploy/chell-test -- /bin/sh

sleep "$ATTACK_STEP_INTERVAL_SECONDS"
run_attempt "Step 8 — curl an unlearned destination (expect: network rule violation, blocked)" \
  kube exec -n "$NS_SCI" deploy/chell-test -- curl -sS --max-time 5 http://google.com

sleep "$ATTACK_STEP_INTERVAL_SECONDS"
run_attempt "Step 9 — wget a learned destination (expect: process profile violation, exit 137)" \
  kube exec -n "$NS_SCI" deploy/chell-test -- wget -qO- --timeout=5 https://www.fastly.com

echo >&2
info "Sequence complete. In the console: Notifications -> Security Events should show"
info "one entry per attempt (sh, then google.com network deny, then wget)."
info "Next: docs/Security_Demo.md Part 3, Step 10 (optional Rewrite-Rule dance) or Part 4 (Chamber 03)."
