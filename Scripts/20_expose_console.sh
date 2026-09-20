#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 20_expose_console — make the NeuVector web console reachable.
# Mode comes from $NEUVECTOR_CONSOLE_EXPOSE in env.sh:
#   port-forward  (default, identical everywhere) — runs in the foreground
#   nodeport      — patches the Service, prints the URL, returns
#   loadbalancer  — patches the Service, prints the external IP, returns
#
# The walkthroughs all assume port-forward. NodePort / LoadBalancer are
# convenience options for Rancher Desktop (k3s ServiceLB) — see
# docs/platform-notes/rancher-desktop.md.

preflight

SVC="neuvector-service-webui"
NS="$NEUVECTOR_NAMESPACE"
PORT="$NEUVECTOR_CONSOLE_PORT"

kube -n "$NS" get svc "$SVC" >/dev/null 2>&1 || \
  die "Service ${SVC} not found in namespace ${NS}. Run Scripts/10_install_neuvector.sh first."

# NeuVector 5.x generates a random admin password on first install and stores
# it in neuvector-bootstrap-secret; fall back to env.sh's setting if that
# Secret isn't there (older chart versions default to admin/admin).
kubectl_cmd="kubectl"
[[ -n "$KUBE_CONTEXT" ]] && kubectl_cmd="kubectl --context ${KUBE_CONTEXT}"
retrieve_hint="Retrieve the password again anytime with:
    ${kubectl_cmd} -n ${NS} get secret neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ \"\\n\" }}'"

admin_password="$(neuvector_admin_password || true)"
if [[ -n "$admin_password" ]]; then
  login_line="Login: admin / ${admin_password}"
else
  admin_password="$NEUVECTOR_ADMIN_PASSWORD"
  login_line="Login: admin / ${admin_password}  (from NEUVECTOR_ADMIN_PASSWORD in env.sh; no bootstrap secret found)"
  retrieve_hint=""
fi

case "$NEUVECTOR_CONSOLE_EXPOSE" in
  port-forward)
    info "Port-forwarding svc/${SVC} — open https://localhost:${PORT}"
    info "$login_line"
    [[ -n "$retrieve_hint" ]] && info "$retrieve_hint"
    info "Press Ctrl-C to stop. To background it instead:  Scripts/20_expose_console.sh &"
    # kubectl port-forward doesn't reconnect on its own — an apiserver
    # streaming timeout, a manager pod restart, or a network blip kills it
    # for good. Loop so the console stays reachable through a long demo.
    while true; do
      kube -n "$NS" port-forward "svc/${SVC}" "${PORT}:8443" || true
      warn "port-forward exited — reconnecting in 3s (Ctrl-C to stop)"
      sleep 3
    done
    ;;

  nodeport)
    info "Patching svc/${SVC} to type NodePort"
    kube -n "$NS" patch svc "$SVC" -p '{"spec":{"type":"NodePort"}}'
    node_port="$(kube -n "$NS" get svc "$SVC" -o jsonpath='{.spec.ports[0].nodePort}')"
    node_ip="$(kube get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
    info "Console: https://${node_ip:-<node-ip>}:${node_port}"
    info "$login_line"
    [[ -n "$retrieve_hint" ]] && info "$retrieve_hint"
    ;;

  loadbalancer)
    info "Patching svc/${SVC} to type LoadBalancer"
    kube -n "$NS" patch svc "$SVC" -p '{"spec":{"type":"LoadBalancer"}}'
    info "Waiting for an external IP (Ctrl-C to stop waiting)…"
    for _ in $(seq 1 30); do
      lb_ip="$(kube -n "$NS" get svc "$SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
      [[ -n "$lb_ip" ]] && break
      sleep 2
    done
    info "Console: https://${lb_ip:-<pending>}:8443"
    info "$login_line"
    [[ -n "$retrieve_hint" ]] && info "$retrieve_hint"
    ;;

  *)
    die "NEUVECTOR_CONSOLE_EXPOSE='${NEUVECTOR_CONSOLE_EXPOSE}' unsupported. Expected: port-forward | nodeport | loadbalancer"
    ;;
esac
