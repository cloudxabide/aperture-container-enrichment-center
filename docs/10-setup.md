# Setup

How to stand up the demo environment. This page is **platform-agnostic** — the
cluster-specific details live in [`platform-notes/`](platform-notes/). Terms
used here are defined in [`00-glossary.md`](00-glossary.md); the overall plan is
[`PLAN.md`](PLAN.md).

---

## 1. Prerequisites

| Tool | Why | Notes |
|------|-----|-------|
| A single-node Kubernetes cluster | Everything runs here | Rancher Desktop (reference platform), or k3s/k3d, kind, minikube. See [`platform-notes/`](platform-notes/). |
| `kubectl` | Talk to the cluster | Rancher Desktop installs it on `PATH`. |
| `helm` v3 | Install NeuVector | — |
| A container tool | Build the `wheatley` image | `nerdctl` (Rancher Desktop / containerd), or `docker` (kind, minikube, Rancher Desktop with the dockerd engine). |
| `envsubst` | Render the manifests | Ships with GNU gettext — `brew install gettext`, or `apt install gettext-base`. |
| `git` | Clone this repo | — |

**Cluster resources:** give the cluster **~6–8 GB RAM** and **4 vCPU**.
NeuVector's control plane plus an Enforcer is the bulk of it. On Rancher Desktop
this is set in the app's *Preferences → Virtual Machine*.

**Cluster requirements NeuVector needs:**

- A CNI NeuVector supports (k3s's default Flannel is fine).
- Permission to run a **privileged** DaemonSet (the Enforcer) with host access.
- Read access to the node's **CRI socket** — the path depends on the runtime
  (see your platform note).
- On a single node you will see **one** Enforcer pod and cannot demonstrate
  cross-*node* east-west segmentation. Pod-to-pod on the one node still works.

---

## 2. One-time configuration

```bash
git clone <this repo> && cd aperture-container-enrichment-center
cp Files/env.sh.example env.sh
$EDITOR env.sh
```

At minimum set:

| Key | Set to |
|-----|--------|
| `PLATFORM` | `rancher-desktop` \| `k3s` \| `k3d` \| `kind` \| `minikube` \| `generic` |
| `KUBE_CONTEXT` | your cluster's context (`kubectl config get-contexts`); leave blank to use the current one |
| `CONTAINER_TOOL` | `nerdctl` or `docker` |
| `NEUVECTOR_CHART_VERSION` | pin an explicit version — see step 3 |
| `NEUVECTOR_CRI_RUNTIME` / `NEUVECTOR_CONTAINERD_SOCK` | per your platform note |
| `REGISTRY` | only if `PLATFORM=generic` (a remote cluster that can't do local image load) |

`env.sh` is git-ignored. Every script sources it through
[`Scripts/lib/common.sh`](../Scripts/lib/common.sh).

---

## 3. Install NeuVector

```bash
Scripts/00_preflight.sh          # checks: cluster reachable, kubectl/helm present
Scripts/10_install_neuvector.sh  # helm upgrade --install into the neuvector namespace
```

`10_install_neuvector.sh` does, in effect:

```bash
helm repo add neuvector "$NEUVECTOR_HELM_REPO"
helm repo update
# pick an explicit version:
helm search repo neuvector/core --versions | head

helm upgrade --install neuvector neuvector/core \
  --namespace "$NEUVECTOR_NAMESPACE" --create-namespace \
  --version "$NEUVECTOR_CHART_VERSION" \
  --set controller.replicas=1 \
  --set manager.svc.type=ClusterIP \
  <platform-specific CRI runtime flags>
```

The **CRI runtime flags** are the one platform-specific part:

| Platform | Flags (verify against `helm show values neuvector/core` for your version) |
|----------|--------------------------------------------------------------------------|
| Rancher Desktop / k3s | `--set k3s.enabled=true --set k3s.runtimePath=/run/k3s/containerd/containerd.sock` |
| kind / generic containerd | `--set containerd.enabled=true --set containerd.path=/run/containerd/containerd.sock` |
| Docker runtime | `--set docker.enabled=true` |

Wait for the control plane:

```bash
kubectl -n neuvector rollout status deploy/neuvector-controller-pod
kubectl -n neuvector get pods
```

You want `neuvector-controller-pod`, `neuvector-manager-pod`,
`neuvector-scanner-pod`, and `neuvector-enforcer-pod` (DaemonSet) all `Running`.

---

## 4. Reach the console

```bash
Scripts/20_expose_console.sh     # kubectl port-forward svc/neuvector-service-webui 8443:8443
```

Then open **https://localhost:8443** and log in with `admin` / `admin`.
Change the password on first login (or set `NEUVECTOR_ADMIN_PASSWORD` and let
the script apply it).

> NodePort / LoadBalancer alternatives exist on Rancher Desktop (k3s ServiceLB)
> — see [`platform-notes/rancher-desktop.md`](platform-notes/rancher-desktop.md).
> `port-forward` is used in all walkthroughs because it behaves identically
> everywhere.

---

## 5. Deploy the demo workloads

```bash
Scripts/30_deploy_apps.sh        # chell-test  -> aperture-sci   (fat image)
Scripts/31_deploy_distroless.sh  # wheatley    -> aperture-labs  (builds + loads the image)
```

Confirm:

```bash
kubectl get pods -n aperture-sci      # chell-test  Running
kubectl get pods -n aperture-labs     # wheatley    Running
```

In the console, **Policy → Groups** should now list `nv.chell-test.aperture-sci`
and `nv.wheatley.aperture-labs` (they may take a minute to appear). New groups
start in **Discover** — let them run a few minutes to build a baseline before
starting the chambers.

---

## 6. Run the chambers

Follow the walkthroughs:

- [`Security_Demo.md`](Security_Demo.md) — Chambers 01–04 (fat image).
- [`Security_Demo_Distroless.md`](Security_Demo_Distroless.md) — Chamber 05
  (distroless).
- Background / threat model: [`Security_Discussion.md`](Security_Discussion.md).

---

## 7. Reset

```bash
Scripts/90_reset_demo.sh         # deletes aperture-sci + aperture-labs
Scripts/90_reset_demo.sh --all   # also `helm uninstall neuvector` + delete the namespace
```

Between demo runs you also want to clear any **Rewrite Rules**, **address
groups**, and **WAF sensors** created during the chambers — the chamber
walkthroughs list their own cleanup steps, and `90_reset_demo.sh` removes the
ones it can.

---

## Platform notes

- [`platform-notes/rancher-desktop.md`](platform-notes/rancher-desktop.md) — the reference platform
- [`platform-notes/k3s-k3d.md`](platform-notes/k3s-k3d.md)
- [`platform-notes/kind.md`](platform-notes/kind.md)
- [`platform-notes/minikube.md`](platform-notes/minikube.md)
