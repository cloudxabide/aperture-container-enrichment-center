# SUSE Security (NeuVector) Walkthrough — Fat Image (`chell-test`)

## Status

Reconciled against [`PLAN.md`](./PLAN.md) chambers 00–04 and 06, and against the
built `Scripts/` and `manifests/`. Commands use the real object names
(`chell-test`, `aperture-sci`, group `nv.chell-test.aperture-sci`); the GLaDOS
names are prose only (see [`00-glossary.md`](./00-glossary.md)).

**Live-test TODO (NeuVector 5.4.x):**

- Confirm the exact console wording for the **Rewrite Rule** dialog and for the
  "implicit deny rule was violated" event.
- Confirm whether an `exec`'d `/bin/bash` is SIGKILLed as well as `/bin/sh` — it
  depends on how the Enforcer scopes the container's entrypoint process (the
  workload's own command is `/bin/bash -c …`, so `bash` is in the baseline).

---

## Overview

This is the **fat-image** track. The workload is `chell-test` —
`nicolaka/netshoot`, a container that ships a shell, `curl`, `wget`, and `grep`
— running in namespace `aperture-sci`. On its own it does exactly one thing: a
`curl` loop to `www.fastly.com` every 5 seconds. That tight, single-process,
single-destination behaviour is what makes every attack step below obviously
anomalous.

Companion tracks:

- [`Security_Demo_Distroless.md`](./Security_Demo_Distroless.md) — Chamber 05,
  the shell-less `wheatley` workload.
- [`Security_Discussion.md`](./Security_Discussion.md) — the threat-model
  narrative behind both.

| Part | Chamber | Proves ([`PLAN.md`](./PLAN.md) §1) |
|------|---------|------------------------------------|
| The Setup + Part 1 | 00 — Discover | **B** — a behavioural baseline is learned with zero app changes |
| Part 2 | 01 — The Weighted Companion Pod | **B** — graduated rollout; learned traffic is unaffected by enforcement |
| Part 3 | 02 — The Combustible Lemon | **A, C** — enforcement is behavioural, process-level, and inside the pod |
| Part 4 | 03 — Domain Block | **D, E** — policy is decoupled from the workload; L7 FQDN egress control |
| Part 5 | 04 — WAF / Layer 7 | **E** — payload inspection inside an already-allowed connection |
| Part 6 | 06 — Closing the loop | **G** — full audit trail |

---

## The Setup

Complete [`10-setup.md`](./10-setup.md) first. By the time you start this
walkthrough:

```bash
Scripts/00_preflight.sh
Scripts/10_install_neuvector.sh
Scripts/20_expose_console.sh    # leave running, or background it
Scripts/30_deploy_apps.sh
```

have all run, and:

```bash
kubectl get pods -n aperture-sci
```
```
NAME                          READY   STATUS    RESTARTS   AGE
chell-test-6b9c8d4f7c-abcde   1/1     Running   0          3m
```

The container is running this loop (from
[`manifests/aperture-sci/chell-test.yaml`](../manifests/aperture-sci/chell-test.yaml)):

```bash
curl -svo /dev/null "https://www.fastly.com" 2>&1 | grep subjectAltName
```

Watch it:

```bash
kubectl logs -f -n aperture-sci deploy/chell-test
```
```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

This validates DNS resolution and the TLS handshake to Fastly every cycle. It is
your **known-good baseline traffic**.

Open the console (**https://localhost:8443**, `admin` / `admin`).

---

## Part 1 — Chamber 00: Discover — establish the baseline

### Step 1 — Watch the traffic being learned

**Network Activity** → find the `aperture-sci` grouping → click `chell-test`.
You should see an **outbound HTTPS connection to `www.fastly.com`** re-drawn
every ~5 seconds, with the destination, protocol (SSL/443), and frequency
recorded.

> 💡 **Tip for the audience:** NeuVector is watching every connection at Layer 7
> — not just IP/port, but protocol and payload. Nothing is being blocked yet.

### Step 2 — Find the group and confirm it is in Discover

**Policy → Groups** → `nv.chell-test.aperture-sci`. New groups start in
**Discover**. Leave it there for **at least 5 minutes** so the baseline is
solid before you enforce anything.

### Step 3 — Review the auto-discovered rules

**Policy → Network Rules**, filtered to `aperture-sci`:

| Field | Value |
|-------|-------|
| **From** | `nv.chell-test.aperture-sci` |
| **To** | `external` |
| **Applications** | `SSL` |
| **Ports** | any |

**Policy → Groups → `nv.chell-test.aperture-sci` → Process Profile Rules** shows
the learned processes: `bash`, `curl`, `grep`, `sleep`.

> 🎯 **Key talking point:** This is the behavioural baseline — "what normal looks
> like" for this one workload, built automatically from observed behaviour, with
> zero changes to the app or its manifest. Everything outside it becomes a
> candidate for enforcement the moment you switch to Protect.

---

## Part 2 — Chamber 01: The Weighted Companion Pod (Monitor → Protect)

*The clean app, the fat image — enforcement turned on, nothing breaks.*

### Step 4 — Move the group to Monitor and re-check the rules

**Policy → Groups → `nv.chell-test.aperture-sci` → Policy Mode → Monitor.**

| Mode | Behaviour |
|------|-----------|
| **Discover** | Learn only — no alerts, no blocks |
| **Monitor** | Alert on anything off-baseline — still no blocks |
| **Protect** | Enforce — off-baseline connections dropped, off-baseline processes SIGKILLed |

Give it a minute. **Notifications → Security Events** stays quiet for
`chell-test` — the loop is entirely within the baseline.

### Step 5 — Switch to Protect

**Policy Mode → Protect → confirm.** Enforcement is active immediately; no
restart.

> 🎯 **Key talking point:** This is a per-group dial. `chell-test` can be in
> Protect while every other workload in the cluster stays in Discover or
> Monitor. Granularity is the point.

### Step 6 — Confirm the legitimate traffic still flows

```bash
kubectl logs -f -n aperture-sci deploy/chell-test
```
```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

Still ticking every ~5 seconds. The `curl → fastly:443` connection was learned
during Discover, so Protect allows it.

> 🎯 **Key talking point:** Zero-trust, not zero-connectivity. The model is "deny
> everything not explicitly allowed" — but the allow-list was built for you from
> real behaviour. Learned traffic is untouched by enforcement.

---

## Part 3 — Chamber 02: The Combustible Lemon (attacking in Protect)

*The same pod, now with an attacker `exec`'d in. The group stays in Protect
throughout this Part.*

Each attempt below is a **single `kubectl exec`**, so you can run them one at a
time and narrate. `Scripts/40_attack_fat.sh` fires the same sequence on a timer
if you would rather not type live.

### Step 7 — Spawn a shell → killed

```bash
kubectl exec -it -n aperture-sci deploy/chell-test -- /bin/sh
```
```
command terminated with exit code 137
```

`sh` is not in the process profile, so the Enforcer SIGKILLs it (`137` = 128 +
SIGKILL). Try `/bin/bash` too — see the Status note about whether the entrypoint
`bash` is distinguished from an interactive one.

**Notifications → Security Events** → one entry per attempt: *Process profile
rule violation by process "sh"*.

> 🎯 **Key talking point:** The attacker's first move — get a shell — fails
> before it runs a single command. Not a signature match; the process simply
> isn't part of what this workload does.

### Step 8 — `curl` to an unlearned destination → blocked (network rule)

```bash
kubectl exec -n aperture-sci deploy/chell-test -- curl -sS --max-time 5 http://google.com
```
```
curl: (28) Connection timed out after 5001 milliseconds
```

`curl` *is* in the baseline (the loop uses it), but `google.com` was never a
learned destination, so the connection is dropped before it leaves the pod's
network namespace.

**Security Events** → *Network rule violation* — Source `chell-test`,
Destination `google.com`, Action **Denied**.

### Step 9 — `wget` to a **learned** destination → blocked (process rule)

```bash
kubectl exec -n aperture-sci deploy/chell-test -- wget -qO- --timeout=5 https://www.fastly.com
```
```
command terminated with exit code 137
```

This is the subtle one. The *destination* (`www.fastly.com:443`) is in the
baseline — but `wget` is a different process from `curl`, and it is not in the
process profile. NeuVector enforces on **the process making the connection**,
not just the destination IP.

**Security Events** → *Process profile rule violation by process "wget"*.

> 🎯 **Key talking point:** An attacker who lands in this container cannot `wget`
> an exfil endpoint or phone home — *even to a host the application itself
> legitimately talks to*. This is how you catch lateral movement and C2 that
> "lives off the land" on allowed infrastructure.

### Step 10 — Optional: the Rewrite-Rule granularity dance

To show how fine-grained the model is, take the interactive path. First
allow-list a shell so you can stay inside the container (in a real incident the
attacker never gets this far — you are deliberately widening the baseline to
demonstrate):

1. On the `sh` violation from Step 7, click **Rewrite Rule** → review the
   red-background warning → **Deploy**.
2. `kubectl exec -it -n aperture-sci deploy/chell-test -- /bin/sh` — now you get
   a prompt.
3. From inside: `curl google.com` → still blocked. **Rewrite Rule** the *network*
   violation → retry → now *"implicit deny rule was violated"* → rewrite that →
   retry → *`grep` not allow-listed* → rewrite → …

Each retry surfaces the next-narrowest thing that isn't yet in the baseline.

> 🎯 **Key talking point:** Every allow is explicit and specific — a process, a
> destination, a port, an application. That granularity is exactly what contains
> an *unknown* exploit: it can only ever do what the workload already does.

`exit` the shell when done (`command terminated with exit code 1` is expected).

---

## Part 4 — Chamber 03: Domain Block (live L7 policy change)

*Policy lives in NeuVector, not the workload. Change it on a running pod — no
restart, no redeploy, no manifest edit.*

### Step 11 — Confirm the baseline loop is still flowing

```bash
kubectl logs -f -n aperture-sci deploy/chell-test
```
```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

### Step 12 — Create an address group for `*.fastly.com`

**Policy → Groups → Add:**

| Field | Value |
|-------|-------|
| **Name** | `fastly-external` |
| **Criteria** | `address=*.fastly.com` |

Without this, a rule targeting `external` would hit *all* outbound traffic, not
just Fastly.

### Step 13 — Add a Deny rule, to the top

**Policy → Network Rules → Add To Top:**

| Field | Value |
|-------|-------|
| **From** | `nv.chell-test.aperture-sci` |
| **To** | `fastly-external` |
| **Ports** | `443` |
| **Action** | **Deny** |
| **Comment** | `Block *.fastly.com` |

> ⚠️ **Order matters.** Rules evaluate top-down, first match wins. **Add To Top**
> puts the Deny ahead of the learned allow.

Click **Deploy**.

### Step 14 — Watch the block take effect

Within one cycle (≤5 s) the log output stops:

```bash
kubectl logs -f -n aperture-sci deploy/chell-test
```

The loop is still running — `curl` still fires every 5 s — but NeuVector now
drops it. **Security Events** shows a steady stream of **Deny** entries
(Source `chell-test`, Destination `www.fastly.com`, Port `443`).

> 🎯 **Key talking point:** Enforcement policy changed on a live workload with no
> restart, no redeploy, and no change to the image or the manifest. The
> application never knows the enforcement layer exists.

### Step 15 — Clean up the block

1. **Policy → Network Rules** — delete `Block *.fastly.com` → **Deploy**.
2. **Policy → Groups** — delete `fastly-external`.

The log output resumes within one cycle.

---

## Part 5 — Chamber 04: WAF / Layer 7 payload

*Network-allowed is not content-allowed.*

### Step 16 — Create a WAF sensor

**Policy → WAF Sensors → Add:**

| Field | Value |
|-------|-------|
| **Name** | `aperture-waf` |
| **Comment** | `Demo WAF sensor for aperture-sci` |

Open it, **Add Rule** twice:

**`sql-injection`** — Context `url`:
```
(?i)(union.*select|select.*from|'\s*or\s*'1'\s*=\s*'1|'\s*or\s*1\s*=\s*1)
```

**`path-traversal`** — Context `url`:
```
(\.\./|%2e%2e%2f|%2e%2e/)
```

**Save.**

### Step 17 — Apply it to the group in Alert

**Policy → Groups → `nv.chell-test.aperture-sci` → WAF** → **Add** →
`aperture-waf`, action **Alert** → **Deploy**.

### Step 18 — Trigger a SQL-injection alert

```bash
kubectl exec -n aperture-sci deploy/chell-test -- \
  curl -sk "https://www.fastly.com/path?id=1%27%20OR%20%271%27%3D%271"
```

The request goes through (sensor is in Alert), but **Security Events** shows a
**WAF** event: sensor `aperture-waf`, rule `sql-injection`, source `chell-test`,
action **Alert**.

> 🎯 **Key talking point:** The network rule allowed this — Fastly on 443 is in
> the baseline. The WAF caught what the network rule can't see: a malicious
> payload *inside* the allowed channel.

### Step 19 — Switch to Deny and verify

**WAF** tab → change `aperture-waf` action to **Deny** → **Deploy**. Repeat the
SQLi request, and test traversal:

```bash
kubectl exec -n aperture-sci deploy/chell-test -- \
  curl -sk "https://www.fastly.com/../../etc/passwd"
```

Both fail now. **Security Events** shows **Deny** WAF events for each.

### Step 20 — WAF cleanup

1. **Policy → Groups → `nv.chell-test.aperture-sci` → WAF** — remove
   `aperture-waf` → **Deploy**.
2. **Policy → WAF Sensors** — delete `aperture-waf`.

---

## Part 6 — Chamber 06: Closing the loop

### Step 21 — Walk the Security Events timeline

**Notifications → Security Events**, oldest to newest. For each: what was
attempted (process, destination, protocol, payload), what NeuVector did, and how
it maps to a real threat — unauthorised egress, C2 callout, exfil, a web-attack
pivot.

> 🎯 **Key talking point:** Every allow and every deny is logged with full
> context — source workload, process, destination, action, timestamp. That is
> the audit trail an IL4/IL5 review asks for, produced as a side effect of
> enforcement.

### Step 22 — Optional: network graph differential

**Network Activity** — blocked attempts render as **red dotted lines**, visually
distinct from the green allowed connection to Fastly. A clear "allowed vs.
blocked" picture for a non-technical audience.

---

## Demo Summary

| Action | Mode | Result |
|--------|------|--------|
| `curl fastly.com` (baseline loop) | Discover / Monitor | ✅ Observed and learned |
| Switch group to Protect | — | Learned rules become enforced policy |
| `curl fastly.com` (baseline loop) | Protect | ✅ Allowed — matches the baseline |
| `kubectl exec … -- /bin/sh` | Protect | 🚫 SIGKILLed (`exit 137`) — process not in profile |
| `curl google.com` | Protect | 🚫 Blocked — destination never learned (network rule) |
| `wget fastly.com` | Protect | 🚫 Blocked — process not in profile, though destination *is* learned |
| Add Deny rule → `*.fastly.com` | Protect | 🚫 Baseline loop stops within 5 s; no workload change |
| Remove Deny rule | Protect | ✅ Baseline loop resumes within 5 s |
| `curl 'fastly.com/?id=… OR 1=1'` | WAF Alert | ⚠️ Allowed but alerted — payload matched |
| `curl 'fastly.com/?id=… OR 1=1'` | WAF Deny | 🚫 Blocked — WAF enforced on the HTTP payload |
| `curl 'fastly.com/../../etc/passwd'` | WAF Deny | 🚫 Blocked — path-traversal rule |

---

## Key Takeaways

- **Behavioural, not signature-based** *(claim A)* — NeuVector models what each
  workload normally does and enforces that. Zero-days built from
  legitimate-looking processes are still caught.
- **Graduated rollout** *(claim B)* — Discover → Monitor → Protect lets you build
  confidence before enforcing. Learned traffic is unaffected when you flip to
  Protect.
- **Process-level, inside the pod** *(claim C)* — the unit of enforcement is the
  container process making the connection, not an IP or port at a perimeter.
  `wget` is blocked to a host `curl` is allowed to reach.
- **Policy decoupled from the workload** *(claim D)* — rules, address groups, and
  WAF sensors live in NeuVector. Change them on a running pod; the app never
  knows.
- **Layer 7 built in** *(claim E)* — FQDN egress control and WAF payload
  inspection, per-workload, with no separate appliance.
- **Full audit trail** *(claim G)* — every allow and deny logged with source,
  process, destination, action, and timestamp.

---

## References

- [`PLAN.md`](./PLAN.md) — thesis, claims A–G, and the full chamber list.
- [`00-glossary.md`](./00-glossary.md) — canonical definitions for every term
  used here.
- NeuVector Docs — [Modes: Discover, Monitor, Protect](https://open-docs.neuvector.com/policy/modes/)
  · [Network Rules](https://open-docs.neuvector.com/policy/networkrules/)
  · [Process Profile Rules](https://open-docs.neuvector.com/policy/processrules/)
  · [DLP & WAF Sensors](https://open-docs.neuvector.com/policy/dlp/)
- SUSE — [SUSE Security (NeuVector) documentation hub](https://documentation.suse.com/cloudnative/security/)
- SUSE Communities — [Zero Trust Runtime Container Security](https://www.suse.com/c/zero-trust-runtime-container-security/)
- Companion: [`Security_Demo_Distroless.md`](./Security_Demo_Distroless.md) ·
  [`Security_Discussion.md`](./Security_Discussion.md)
