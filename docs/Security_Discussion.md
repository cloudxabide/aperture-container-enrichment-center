# Security Discussion

Working notes for the narrative around SUSE Security (NeuVector). Expect this to grow several sections over time; the first covers distroless / shell-less containers.

---

## Distroless ("no-shell") containers

### Where this comes from

In a conversation with a customer new to Kubernetes and containers:

> **Customer:** "Distroless removes the ability for someone to hack in — there's no shell."
> **Me:** *(nodding along)* "…well, not exactly."

Removing `bash`/`sh` is a real improvement: it breaks a large class of automated exploit scripts and closes the "exec in and use the built-in tools" path. But it does not make the container immune to compromise. An attacker who gets a foothold can pivot to application-layer techniques, and the app's own vulnerabilities are untouched by stripping the OS. This section is the narrative for *why* — and where SUSE Security fits.

### Why "no shell" isn't the whole story

| Attack technique | Why "no shell" doesn't stop it | How SUSE Security (NeuVector) addresses it |
|:-----------------|:-------------------------------|:------------------------------------------|
| **Living off the Application** — drive the app's own runtime (Python / Node / Java / Ruby) to execute code, open a reverse connection, and read/exfiltrate files through native libraries | The interpreter *is* the runtime — no `sh`, `curl`, or `wget` required | Zero-Trust process profiling: the learned baseline is the app's expected process tree, so a child process or exec it never normally performs is flagged and (in Protect) killed. Layer 7 egress rules drop the reverse connection regardless of what spawned it |
| **SSRF / application vulnerabilities** — force the app to hit the kubelet API, internal services, or cloud metadata (`169.254.169.254`); path traversal / LFI to read mounted files; insecure deserialization for in-memory RCE | Stripping the OS patches nothing in the app; the vulnerable code path is still there | Built-in WAF inspects inbound HTTP for OWASP-class payloads (deserialization, traversal) at the pod. Layer 7 micro-segmentation permits egress only to baselined destinations and protocols, so SSRF to metadata or the kubelet is denied |
| **Service-account token abuse** — read the token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`, then drive the API server with the attacker's own `kubectl` from outside | Reading a file needs no shell, and the token is mounted by default | File-system monitoring flags reads/writes outside the baseline. Network rules can deny pod → API-server traffic that was never baselined; DLP can detect token-shaped data leaving in outbound traffic |
| **Bring Your Own Land (BYOL)** — exploit a file-write/upload flaw to drop a statically linked `busybox` / Go reverse shell / `kubectl` into `/tmp`, then trigger it via the app | A static binary carries its own dependencies — the missing OS libraries are irrelevant | File-system monitoring detects the write to `/tmp`; process profiling detects the new binary executing — it isn't in the allow-list — and blocks it in Protect mode |
| **Fileless / memory execution** — buffer-overflow shellcode, or `memfd_create` an anonymous in-RAM ELF and execute it, leaving nothing on disk (also defeats a read-only root filesystem) | Never touches the filesystem or a shell binary | Process and syscall monitoring catch the anomalous execution and unexpected system calls, and block the action before the payload runs |
| **Kernel exploit / container breakout** — use app-layer RCE to trigger a kernel flaw (Dirty Pipe, CVE-2022-0847; eBPF) or a `runc` / `containerd` escape to reach the worker node | Isolation is what's under attack, not the container's toolset — image contents don't matter | Host- and kernel-level monitoring flags privilege escalation, suspicious syscalls, and breakout attempts, and can isolate the compromised pod |

### The point

Removing shells is solid defense-in-depth, not a silver bullet. A complete posture pairs distroless images with read-only root filesystems, dropped Linux capabilities, strict network policy, and continuous dependency patching — and then adds runtime enforcement that works regardless of what's in the image.

SUSE Security (NeuVector) is that layer. It learns a workload's normal process, network, and file behavior in **Discover** mode, then blocks anything outside that baseline in **Protect** mode, using a Zero-Trust model that operates independently of the container's OS or available utilities. The image can be as minimal or as fat as you like — the behavioral control is the same.

See [`Security_Demo_Distroless.md`](./Security_Demo_Distroless.md) for a hands-on demo of this against a distroless workload.

---

## References

- GoogleContainerTools — [distroless](https://github.com/GoogleContainerTools/distroless) — what "distroless" actually removes (shell, package manager, coreutils) and what it leaves behind.
- Kubernetes — [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/) — how `kubectl debug` attaches tooling to a shell-less pod regardless of image contents.
- [GTFOBins](https://gtfobins.github.io/) — catalogue of "living off the land" techniques that abuse interpreters/binaries already present, no `sh` required.
- MITRE ATT&CK — [T1059 Command and Scripting Interpreter](https://attack.mitre.org/techniques/T1059/) · [T1105 Ingress Tool Transfer](https://attack.mitre.org/techniques/T1105/) — the interpreter-abuse and "bring your own land" pivots in the table.
- SUSE Communities — [Zero Trust Runtime Container Security](https://www.suse.com/c/zero-trust-runtime-container-security/) — where NeuVector's behavioral model fits.
- SUSE — [SUSE Security (NeuVector) documentation hub](https://documentation.suse.com/cloudnative/security/)
