# Platform notes — k3s / k3d

For a standalone **k3s** install or a **k3d** (k3s-in-Docker) cluster. Behaves
almost identically to Rancher Desktop (which is k3s underneath) — see
[`rancher-desktop.md`](rancher-desktop.md) for the shared k3s details.

## `env.sh` values

```bash
# standalone k3s on a Linux host
PLATFORM="k3s"
KUBE_CONTEXT="default"                       # or whatever your kubeconfig calls it
CONTAINER_TOOL="nerdctl"                     # k3s bundles containerd
CONTAINERD_NAMESPACE="k8s.io"
NEUVECTOR_CRI_RUNTIME="k3s"
NEUVECTOR_CONTAINERD_SOCK="/run/k3s/containerd/containerd.sock"

# k3d
PLATFORM="k3d"
KUBE_CONTEXT="k3d-<cluster-name>"
CONTAINER_TOOL="docker"                      # you build with the host Docker, then import
NEUVECTOR_CRI_RUNTIME="k3s"
NEUVECTOR_CONTAINERD_SOCK="/run/k3s/containerd/containerd.sock"
```

## Getting the `wheatley` image into the cluster

| | Mechanism |
|--|-----------|
| **k3s** | `nerdctl --namespace k8s.io build ...` (as Rancher Desktop), or `sudo k3s ctr images import <tar>` |
| **k3d** | `docker build ...` then `k3d image import wheatley-server:latest -c <cluster>` — `push_image` does this when `PLATFORM=k3d` |

## Notes

- k3s ships Traefik, ServiceLB, and local-path — `LoadBalancer` and PVCs work.
- k3d runs the "node" as a container; `hostPath`/socket mounts the Enforcer
  needs are already wired by k3d's k3s image, but confirm the Enforcer pod
  reaches `Running` and check its logs if network events don't appear.
- Single control-plane node ⇒ one Enforcer ⇒ no cross-node segmentation demo.
