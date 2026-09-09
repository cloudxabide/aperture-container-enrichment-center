# Platform notes — Rancher Desktop

Rancher Desktop is this repo's **reference platform**: every chamber was
authored and tested here. This page collects the bits that are specific to it.
Everything not on this page is platform-neutral and lives in
[`../10-setup.md`](../10-setup.md).

## What Rancher Desktop gives you

- A single-node **k3s** cluster (kube context: `rancher-desktop`).
- **containerd** as the container engine by default, driven with `nerdctl`
  (there is also a `dockerd (moby)` engine option — see the bottom of this page).
- Because it's k3s: **Traefik** ingress, **ServiceLB (Klipper)** for
  `type: LoadBalancer`, and the **local-path** storage provisioner are all
  preinstalled. `LoadBalancer` services and PVCs work with no extra setup.
- `kubectl`, `nerdctl`, `helm`, and `docker` (shim) are added to your `PATH` by
  the installer — accept the "update PATH" prompt. The demo assumes these
  resolve to Rancher Desktop's copies.

## `env.sh` values for Rancher Desktop

```bash
PLATFORM="rancher-desktop"
KUBE_CONTEXT="rancher-desktop"
CONTAINER_TOOL="nerdctl"
CONTAINERD_NAMESPACE="k8s.io"
NEUVECTOR_CRI_RUNTIME="k3s"
NEUVECTOR_CONTAINERD_SOCK="/run/k3s/containerd/containerd.sock"
NEUVECTOR_CONSOLE_EXPOSE="port-forward"   # or "loadbalancer" / "nodeport" — see below
REGISTRY=""                              # local image load; no registry needed
```

## Resources

Set in **Rancher Desktop → Preferences → Virtual Machine**: at least **6 GB RAM**
(8 GB comfortable) and **4 CPU**. NeuVector's controller + manager + scanner +
enforcer plus the two demo workloads is the load.

## Building the `wheatley` image

With the containerd engine, an image must be built into (or loaded into) the
**`k8s.io` containerd namespace** or the kubelet can't see it:

```bash
nerdctl --namespace k8s.io build -t wheatley-server:latest apps/wheatley
nerdctl --namespace k8s.io image ls | grep wheatley
```

`Scripts/lib/common.sh`'s `build_image` does this automatically when
`PLATFORM=rancher-desktop` and `CONTAINER_TOOL=nerdctl`; `push_image` then just
verifies the image is present. No registry involved.

> Plain `nerdctl build` (without `--namespace k8s.io`) puts the image in the
> `default` containerd namespace, where `ImagePullBackOff` will be your reward.

## Installing NeuVector

Use the k3s runtime settings:

```bash
helm upgrade --install neuvector neuvector/core \
  --namespace neuvector --create-namespace \
  --version "$NEUVECTOR_CHART_VERSION" \
  --set k3s.enabled=true \
  --set k3s.runtimePath=/run/k3s/containerd/containerd.sock \
  --set controller.replicas=1 \
  --set manager.svc.type=ClusterIP
```

`Scripts/10_install_neuvector.sh` applies these when `NEUVECTOR_CRI_RUNTIME=k3s`.
Always confirm the value names against your chart version:
`helm show values neuvector/core | less`.

## Reaching the console

`port-forward` (the walkthrough default) works unchanged:

```bash
kubectl -n neuvector port-forward svc/neuvector-service-webui 8443:8443
```

Because k3s ships ServiceLB, you *can* instead expose it directly:

```bash
# LoadBalancer — gets an address on your host network via Klipper
kubectl -n neuvector patch svc neuvector-service-webui \
  -p '{"spec":{"type":"LoadBalancer"}}'
kubectl -n neuvector get svc neuvector-service-webui   # note EXTERNAL-IP

# or NodePort
kubectl -n neuvector patch svc neuvector-service-webui \
  -p '{"spec":{"type":"NodePort"}}'
```

Set `NEUVECTOR_CONSOLE_EXPOSE=loadbalancer` (or `nodeport`) in `env.sh` to have
`Scripts/20_expose_console.sh` do this for you. The chamber docs still describe
`port-forward` so they read the same on every platform.

## Single-node limitation

One node ⇒ one Enforcer pod ⇒ no cross-*node* east-west traffic to segment.
Every chamber here is about **process-level** and **egress** enforcement on a
single node, so this doesn't affect the demo — but say so if an audience asks
about multi-node microsegmentation.

## If you use the dockerd (moby) engine instead

Rancher Desktop → Preferences → Container Engine → `dockerd (moby)`. Then:

```bash
CONTAINER_TOOL="docker"
NEUVECTOR_CRI_RUNTIME="docker"       # helm: --set docker.enabled=true
```

Images built with `docker build` are visible to the kubelet directly — no
`--namespace k8s.io`, no load step. `build_image` / `push_image` handle this
(`push_image` becomes a no-op with a note).
