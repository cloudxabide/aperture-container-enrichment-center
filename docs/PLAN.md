# Project Plan — Aperture Container Enrichment Center

A hands-on demo of **SUSE Security (NeuVector) 5.x** on a single-node Kubernetes
cluster. Built and tested on **Rancher Desktop**, but written to run on any
single-node cluster (k3s/k3d, kind, minikube, or a remote cluster) with the
Rancher-specific steps isolated and clearly labelled.

`Project.md` is the one-paragraph charter. This is the working plan.

---

## 1. What we are trying to prove

One thesis, seven supporting claims. Every test chamber maps to at least one.

| # | Claim | Chambers |
|---|-------|----------|
| A | Runtime security is **behavioral, not signature-based** — catches zero-days and "living off the land" | 02, 05 |
| B | **Graduated rollout** (Discover → Monitor → Protect) de-risks enforcement — watch first, then act | 00, 01 |
| C | Enforcement is **process-level and per-workload**, inside the pod — not IP/port at a perimeter | 02, 05 |
| D | Policy is **decoupled from the workload** — change it live, no restart, no image or manifest change | 03 |
| E | **Layer 7 is built in** — FQDN egress control + WAF payload inspection, no separate appliance | 03, 04 |
| F | Image hardening (distroless) and runtime enforcement are **complementary, not substitutes** | 05 |
| G | **Full audit trail** — every allow/deny logged with context (the IL4/IL5 compliance angle) | 06 |

---

## 2. Decisions (settled)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Object naming | Kubernetes objects keep the names already written into the walkthroughs: `chell-test` (fat app), `wheatley` (distroless app), namespaces `aperture-sci` / `aperture-labs`. The GLaDOS names (`weighted-companion-pod`, `combustible-lemon`, `glados-enforcer-mode`, `dpi-sentry-turret`) are **narrative aliases used in prose only** — decoded in the glossary. |
| 2 | Fat-app image | `nicolaka/netshoot` — it is deliberately the "fat image" foil to distroless. Baseline is driven by a single `curl` loop so the learned process profile stays tight. |
| 3 | Scope | Core = Chambers 00–05 plus the 06 wrap-up. Chamber 07 (Bring Your Own Land) is a short bolt-on to 05. Chamber 08 (admission control / CVE scan) is deferred to a second milestone. |
| 4 | NeuVector install | Helm chart (`neuvector/core`), pinned to an explicit version in `env.sh` (latest 5.4.x line). Not the operator. |
| 5 | Images | Default to local image load (self-contained on RD/kind/minikube). `REGISTRY` in `env.sh` is the override for remote clusters. Only `wheatley` is built locally; everything else pulls from public registries. |
| 6 | NeuVector console access | `kubectl port-forward` in every walkthrough (identical on all platforms). NodePort / LoadBalancer mentioned only in `docs/platform-notes/rancher-desktop.md`. |
| 7 | AI/agent instructions | One always-loaded `CLAUDE.md` (repo conventions) plus one project skill, `.claude/skills/add-chamber/`, for the recurring "scaffold a test chamber" workflow. Doc-authoring, demo-prep, and script-scaffold skills are deliberately deferred until the pattern has repeated. |

---

## 3. Test chambers

Core set is **00–05**. 06 is a wrap-up, not a test. 07–08 are stretch.

### Chamber 00 — "It's just a web app" (setup / Discover)
- **Workloads:** `chell-test` in `aperture-sci`; `wheatley` in `aperture-labs`.
- **Do:** deploy both; generate baseline traffic (fat app: `curl` loop to
  `fastly.com` every 5s; `wheatley`: serves HTTP on `:8080`); leave the
  NeuVector groups in **Discover** for a few minutes.
- **Proves:** B — NeuVector learns a behavioral model with zero changes to the
  app. Establishes "known good".
- **NV surface:** Network Activity graph; auto-discovered Network + Process
  rules; Groups (`nv.<workload>.<namespace>`).

### Chamber 01 — The Weighted Companion Pod (clean app, fat image)
- **Workload:** `chell-test` (`nicolaka/netshoot` — has shell, `curl`, `wget`).
- **Do:** review the learned rules in **Monitor**; flip the group to
  **Protect**; confirm the `curl` loop keeps working.
- **Proves:** B, plus "zero-trust is not zero-connectivity" — learned traffic is
  unaffected by enforcement.
- **NV surface:** Policy → Groups → Policy Mode; Policy → Network Rules;
  Security Events (quiet).

### Chamber 02 — The Combustible Lemon (interactive attacker, fat image)
- **Do (in Protect):** `kubectl exec` into the pod, then attempt, in order:
  1. spawn `/bin/sh` → killed, `exit 137`
  2. `curl google.com` → blocked (destination never learned)
  3. `wget https://www.fastly.com` → blocked (**known destination, unknown
     process**)
  4. the Rewrite-Rule granularity dance: allow `curl`, retry, hit implicit-deny,
     allow that, retry, hit `grep` not allow-listed, allow `grep`, …
- **Proves:** A + C — enforcement is on the *process making the connection*, not
  the IP. Catches lateral movement / C2 / exfil even to legitimate destinations.
- **NV surface:** Security Events; Rewrite Rule dialog; Process Profile Rules.
- **Note:** the dance is fiddly to run live. `Scripts/40_attack_fat.sh` fires
  the attempts on a timer so the presenter can narrate instead of type.

### Chamber 03 — Domain Block (live L7 policy change)
- **Do:** create address group `fastly-external` (`address=*.fastly.com`); add a
  **Deny** network rule *to top*; watch the still-running `curl` loop stop
  within one 5s cycle; remove the rule and watch traffic resume.
- **Proves:** D + E — policy lives in NeuVector, independent of the workload. No
  restart, no redeploy, no manifest edit.
- **NV surface:** Policy → Groups (address group); Network Rules (rule order,
  "Add To Top"); Security Events (Deny stream).

### Chamber 04 — WAF / Layer 7 payload
- **Do:** create a WAF sensor with SQL-injection + path-traversal patterns;
  apply to the group in **Alert**; fire
  `curl "…/path?id=1' OR '1'='1"` from inside the (allowed) channel to Fastly;
  observe the alert; switch the sensor to **Deny**; retry; observe the block;
  also test `…/../../etc/passwd`.
- **Proves:** E — network-allowed is not content-allowed. App-layer protection
  with no separate appliance; per-workload posture.
- **NV surface:** Policy → WAF Sensors; Group → WAF tab; Security Events
  (type: WAF).

### Chamber 05 — The Distroless Turret (shell-less image)
- **Workload:** `wheatley` — static Go binary on
  `gcr.io/distroless/static-debian12:nonroot` — in `aperture-labs`.
- **Do:**
  1. `kubectl exec -- /bin/sh` → fails at the **image layer**
     ("no such file"). *Not NeuVector.* Defense in depth.
  2. `kubectl debug --image=busybox --target=wheatley` → an ephemeral container
     attaches (the real foothold — a Kubernetes side door image hardening
     cannot close).
  3. In **Monitor**: `wget` the EICAR test file → succeeds, logged as a process
     + network anomaly.
  4. In **Protect**: retry — the busybox process is killed / egress blocked.
- **Proves:** F + A + C — image hardening and runtime enforcement are different
  guarantees. Separation of concerns: **RBAC governs who can attach; NeuVector
  governs what the attached thing can do.**
- **NV surface:** Groups / Modes; Process Profile Rules; Security Events
  (ephemeral-container event — exact wording TBD per NV version).

### Chamber 06 — Closing the loop (not a test)
- Walk the Security Events timeline; optional Network Graph differential (green
  allowed vs. red blocked). Map to a real threat narrative. Carries claim G.

### Chamber 07 (stretch) — Bring Your Own Land
- From `Security_Discussion.md`: write a static binary to `/tmp` and execute it
  → filesystem-write + process-profile violation. Small addition to Chamber 05;
  proves file monitoring + process profiling catch dropped tooling.

### Chamber 08 (stretch / second milestone) — Admission control + image scan
- NeuVector scans the registry image for CVEs; admission control blocks a
  deliberately vulnerable image. Proves "shift-left + runtime in one platform".
  Needs a CVE-laden image and an admission webhook — out of scope for the first
  pass.

---

## 4. Common environment file

`Files/env.sh.example` is committed; the user copies it to `env.sh` at the repo
root (git-ignored) and edits. Every script sources it via
`Scripts/lib/common.sh`. See `Files/env.sh.example` for the authoritative list;
summary of keys:

| Group | Keys |
|-------|------|
| Platform | `PLATFORM`, `KUBECTL`, `KUBE_CONTEXT` |
| Image build / delivery | `CONTAINER_TOOL`, `CONTAINERD_NAMESPACE`, `REGISTRY`, `IMAGE_PULL_POLICY` |
| NeuVector | `NEUVECTOR_NAMESPACE`, `NEUVECTOR_HELM_REPO`, `NEUVECTOR_CHART_VERSION`, `NEUVECTOR_CRI_RUNTIME`, `NEUVECTOR_CONTAINERD_SOCK`, `NEUVECTOR_CONSOLE_EXPOSE`, `NEUVECTOR_CONSOLE_PORT`, `NEUVECTOR_ADMIN_PASSWORD` |
| Demo workloads | `NS_SCI`, `NS_LABS`, `CLEAN_APP_IMAGE`, `DISTROLESS_APP_IMAGE`, `DEBUG_IMAGE` |
| Test parameters | `BASELINE_TARGET_URL`, `BASELINE_INTERVAL_SECONDS`, `EICAR_URL` |
| Optional | `DEMO_HOSTNAME` |

---

## 5. Glossary (authoritative — `docs/00-glossary.md` will hold the full copy)

| Term | Meaning in this repo |
|------|----------------------|
| **Discover / Monitor / Protect** | NeuVector policy modes: learn-only / alert-only / enforce. Set per Group. |
| **Group** | NeuVector's unit of policy. Auto-named `nv.<workload>.<namespace>`, e.g. `nv.chell-test.aperture-sci`. |
| **Network Rule** | Allow/Deny for a (source group → destination, ports, application) tuple. Evaluated top-down; first match wins. |
| **Process Profile Rule** | Allow-list entry for a process name/path inside a workload. Why `wget` is blocked even when `curl` to the same host is allowed. |
| **Rewrite Rule** | The one-click allow-list entry NeuVector suggests from a violation event. The Chamber 02 "granularity dance" is repeated Rewrite-Rule deploys. |
| **Address Group** | A named group matched by FQDN/CIDR (`address=*.fastly.com`), so a rule can target one domain instead of all `external`. |
| **WAF Sensor** | A set of L7 payload patterns (SQLi, traversal, …) applied per-Group; action Alert or Deny. |
| **Enforcer** | The privileged NeuVector DaemonSet pod on each node that does the actual blocking. One pod total on single-node Rancher Desktop. |
| **Controller / Manager / Scanner** | Control plane / web console / image-CVE scanner components. |
| **Baseline** | The learned behavioral model (processes + network + files) captured during Discover. |
| **`aperture-sci` / `aperture-labs` / `neuvector`** | Namespaces: fat-image demo / distroless demo / NeuVector install. |
| **GLaDOS aliases** | `weighted-companion-pod` = the clean app; `combustible-lemon` = the same pod once an attacker is exec'd in; `glados-enforcer-mode` = Protect mode; `dpi-sentry-turret` = the Enforcer. Prose only. |

---

## 6. Platform-agnostic strategy

The walkthroughs (NeuVector UI, `kubectl exec` / `debug`, EICAR, WAF, all policy
steps) are already fully portable. Only **five** touch-points are
platform-specific; all five are isolated in `env.sh` + `Scripts/lib/common.sh`
behind a `PLATFORM` switch.

| Touch-point | rancher-desktop | k3s / k3d | kind | minikube | generic |
|-------------|-----------------|-----------|------|----------|---------|
| Get image to kubelet | `nerdctl -n k8s.io build/load` | `k3s ctr images import` or registry | `kind load docker-image` | `minikube image load` | push to `$REGISTRY` |
| Reach NV console | `kubectl port-forward` (NodePort/LB optional) | same | `kubectl port-forward` | `kubectl port-forward` / `minikube service` | `kubectl port-forward` |
| NV Helm CRI values | `k3s` runtime, sock `/run/k3s/containerd/containerd.sock` | same | `containerd`, `/run/containerd/containerd.sock` | driver-dependent | cluster-dependent |
| kube context name | `rancher-desktop` | `k3d-<name>` | `kind-<name>` | `minikube` | — |
| Resource sizing | RD GUI (give it ~6–8 GB) | VM / host | `kind` config | `--memory` flag | — |

A `push_image()` helper in `common.sh` that switches on `$PLATFORM` covers row 1.
Rows 3–4 are `env.sh` values. Rows 2 and 5 are documentation notes.

### Rancher-Desktop-specific callouts (label these clearly in the docs)

- **`$PATH` update** (per `Project.md`): RD installs `kubectl`, `nerdctl`,
  `helm`, and `docker` shims into `PATH` — the demo assumes these resolve to
  RD's copies.
- **Container engine = containerd**, not dockerd/moby. If RD is switched to the
  `dockerd (moby)` engine, the image-delivery step changes (`docker build`, and
  the image is already visible to the kubelet — no `nerdctl -n k8s.io`).
- **containerd namespace `k8s.io`** — images built with `nerdctl` are invisible
  to the kubelet unless built/loaded into that containerd namespace.
- **RD runs k3s under the hood** → Traefik ingress, ServiceLB (Klipper), and
  `local-path` storage are preinstalled, so `LoadBalancer` services and PVCs
  work with no MetalLB / CSI setup. Non-k3s platforms may need `port-forward`.
- **NeuVector Helm**: use the `k3s` runtime settings and containerd socket
  `/run/k3s/containerd/containerd.sock`.
- **Single node**: the Enforcer DaemonSet has exactly one pod; you cannot demo
  cross-*node* east-west segmentation. Pod-to-pod on the one node still demos
  fine — set audience expectations.

---

## 7. Proposed repo structure

```
.
├── README.md                     # what it is, prereqs, 5-line quickstart
├── Project.md                    # charter (keep as-is)
├── CLAUDE.md                     # repo conventions for AI agents + humans
├── .gitignore                    # env.sh, *.local
├── Files/
│   └── env.sh.example            # committed template (see §4); copied to ./env.sh
├── Images/                       # loose image assets referenced by the docs
├── .claude/
│   └── skills/
│       └── add-chamber/SKILL.md  # scaffold a new test chamber
├── docs/
│   ├── PLAN.md                   # this file
│   ├── 00-glossary.md            # §5
│   ├── 10-setup.md               # cluster assumptions + NeuVector install (platform-agnostic)
│   ├── Security_Demo.md          # move existing here; folds in Chambers 01–04
│   ├── Security_Demo_Distroless.md   # move existing here; Chamber 05
│   ├── Security_Discussion.md    # move existing here; concept notes / Chamber 07 seed
│   └── platform-notes/
│       ├── rancher-desktop.md    # §6 callouts — the only Rancher-specific doc
│       ├── k3s-k3d.md
│       ├── kind.md
│       └── minikube.md
├── manifests/
│   ├── 00-namespaces.yaml
│   ├── aperture-sci/             # chell-test Deployment + Service + baseline loop
│   └── aperture-labs/            # wheatley Deployment + Service
├── apps/
│   └── wheatley/                 # main.go + Dockerfile (multi-stage → distroless)
└── Scripts/                      # capital S — matches existing doc references
    ├── lib/common.sh             # source env.sh; kubectl wrapper; push_image() by PLATFORM
    ├── 00_preflight.sh           # check context, node ready, CNI, helm present
    ├── 10_install_neuvector.sh   # helm install with per-platform CRI values
    ├── 20_expose_console.sh      # port-forward | nodeport | lb per env.sh
    ├── 30_deploy_apps.sh         # clean app → aperture-sci        (already referenced in docs)
    ├── 31_deploy_distroless.sh   # build + load wheatley, deploy → aperture-labs (already referenced)
    ├── 40_attack_fat.sh          # optional: scripted Chamber 02 attempts on a timer
    └── 90_reset_demo.sh          # delete demo namespaces; flag to also remove NeuVector
```

---

## 8. Build order

1. `Files/env.sh.example` + `.gitignore` + `Scripts/lib/common.sh` + `CLAUDE.md` +
   `.claude/skills/add-chamber/SKILL.md` — the portability spine and the
   agent-instruction layer. **(done)**
2. `docs/00-glossary.md`, `docs/10-setup.md`, `docs/platform-notes/*` (rancher-desktop
   + k3s-k3d / kind / minikube), and move the three `Security_*.md` into `docs/`. **(done)**
3. `apps/wheatley/` (main.go + Dockerfile) + `manifests/` + `Scripts/00,10,20,30,31`.
4. Reconcile `Security_Demo.md` / `Security_Demo_Distroless.md` against the
   chamber list and the real object names; tighten the order of operations
   (both docs flag this themselves).
5. `Scripts/40_attack_fat.sh` + `Scripts/90_reset_demo.sh`.
6. Dry-run end-to-end on Rancher Desktop, then a second pass on kind to prove
   the `PLATFORM` switch.

---

## 9. Known inconsistencies to fix during the build

- `Security_Demo.md` Step 7 shows `exit 137` for `/bin/sh` while the group is
  already in Protect — the doc's own TODO calls the order of operations loose.
  Fix the sequencing when folding it into Chamber 02.
- Both demo docs reference `Scripts/30_deploy_apps.sh` / `31_deploy_distroless.sh`
  and `env.sh` that do not exist yet — build step 1 and 3 create them.
- `Security_Demo_Distroless.md` uses `<your-registry>/wheatley-server:latest`
  with no registry defined — resolved by `DISTROLESS_APP_IMAGE` / `REGISTRY` in
  `env.sh` and local-load default.
- No `.gitignore` yet; `env.sh` may contain a registry path or credentials and
  must be ignored.
