# Glossary

Canonical definitions for terms used across this repo. When a walkthrough uses
one of these, it means exactly what is written here.

## NeuVector concepts

| Term | Definition |
|------|------------|
| **Discover mode** | A group's policy mode where NeuVector only *learns* behaviour. No alerts, no blocks. The starting point for every workload. |
| **Monitor mode** | Policy mode where NeuVector *alerts* on anything outside the learned baseline but does not block it. Used to build confidence before enforcing. |
| **Protect mode** | Policy mode where NeuVector *enforces* — violations of the baseline are blocked (network connections dropped, processes killed with SIGKILL / `exit 137`). |
| **Group** | NeuVector's unit of policy. Workload groups are auto-named `nv.<workload>.<namespace>` — e.g. `nv.chell-test.aperture-sci`. Policy mode, network rules, process rules, and WAF sensors are all attached at the group level. |
| **Baseline** | The learned model of a workload's normal behaviour — its expected processes, network destinations/protocols, and file access — captured during Discover mode. Enforcement in Protect mode is "allow the baseline, deny everything else". |
| **Network Rule** | An allow or deny entry for a `(source group → destination, ports, application)` tuple. Rules are evaluated top-to-bottom; the first match wins. "Add To Top" places a rule ahead of the auto-learned allow rules. |
| **Process Profile Rule** | An allow-list entry for a specific process (by name/path) inside a workload. This is why `wget` can be blocked even when `curl` to the same host on the same port is allowed — the *process* is not in the profile. |
| **Rewrite Rule** | The one-click allow-list entry NeuVector proposes from a violation event in Security Events. Deploying it adds the observed process/connection to the baseline. The Chamber 02 "granularity dance" is a sequence of these. |
| **Address Group** | A group defined by address criteria (FQDN or CIDR), e.g. `address=*.fastly.com`. Lets a rule target one domain instead of the catch-all `external`. |
| **WAF Sensor** | A named set of Layer 7 payload patterns (SQL injection, path traversal, XSS, …) with an action of Alert or Deny. Applied per group, it inspects HTTP/HTTPS request content inside otherwise-allowed connections. |
| **DLP Sensor** | Like a WAF sensor but for data *leaving* the workload — pattern-matches outbound payloads (e.g. token- or PII-shaped data). Not exercised in the core chambers; noted in `Security_Discussion.md`. |
| **Security Events** | `Notifications → Security Events` in the console. The audit log of every violation (and, in Monitor mode, every would-be violation) with source, destination, process, action, and timestamp. |
| **Network Activity** | The live service-to-service graph in the console. Allowed connections render green; blocked ones can render as red dotted lines. |

## NeuVector components

| Component | Role |
|-----------|------|
| **Enforcer** | Privileged DaemonSet pod, one per node. Does the actual runtime inspection and blocking. On single-node Rancher Desktop there is exactly one Enforcer pod. |
| **Controller** | Control plane — holds policy, coordinates Enforcers. Chart default is 3 replicas; reduced to 1 for single-node demos. |
| **Manager** | The web console (UI). Exposed here via `kubectl port-forward`. |
| **Scanner** | Image vulnerability (CVE) scanner. Used by the deferred Chamber 08. |

## This repo's workloads and namespaces

| Name | Kind | Namespace | Notes |
|------|------|-----------|-------|
| `chell-test` | Deployment | `aperture-sci` | The "fat image" workload — `nicolaka/netshoot`, has a shell, `curl`, `wget`. Runs a `curl` loop to `www.fastly.com` every 5s as baseline traffic. |
| `wheatley` | Deployment | `aperture-labs` | The distroless workload — a static Go HTTP server on `gcr.io/distroless/static-debian12:nonroot`. No shell, no package manager. Serves `:8080`. |
| `neuvector` | namespace | — | Where the NeuVector Helm release is installed. |

## GLaDOS / Portal aliases (prose only)

These names appear in narration and `Project.md`. They are **not** real
Kubernetes or NeuVector objects — do not create anything named after them.

| Alias | Refers to |
|-------|-----------|
| **weighted companion pod** | the clean app (`chell-test`) before anyone tampers with it |
| **combustible lemon** | the same pod once an attacker has `kubectl exec`'d in and is running unauthorised tools |
| **glados-enforcer-mode** | switching a group to Protect mode |
| **dpi-sentry-turret** | the NeuVector Enforcer doing deep packet inspection and dropping connections |
| **Test Chamber NN** | a single self-contained demo scenario — see [`PLAN.md`](PLAN.md) §3 |

## Platform terms

| Term | Definition |
|------|------------|
| **`$PLATFORM`** | The switch in `env.sh` (`rancher-desktop` \| `k3s` \| `k3d` \| `kind` \| `minikube` \| `generic`) that selects the handful of cluster-specific behaviours — see [`PLAN.md`](PLAN.md) §6. |
| **containerd `k8s.io` namespace** | The containerd (not Kubernetes) namespace the kubelet reads images from. On Rancher Desktop/k3s an image built with `nerdctl` is invisible to the cluster unless it lands here. |
| **ServiceLB / Klipper** | k3s's built-in `LoadBalancer` implementation. Present on Rancher Desktop, so `type: LoadBalancer` services get an address with no MetalLB. Not present on kind/minikube. |
| **Ephemeral container** | A container added to a *running* pod via `kubectl debug`. Shares the pod's network namespace (and usually the target's process namespace). The foothold technique in Chamber 05 — it works regardless of how minimal the pod's image is. |
| **EICAR test file** | A harmless, industry-standard string that every AV/EDR product recognises as "malware" for testing. Safe to download live in a demo. Pulled from `secure.eicar.org` in Chamber 05. |
