# Platform notes — kind

[kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker). Useful as the
"prove the `$PLATFORM` switch works" second target.

## `env.sh` values

```bash
PLATFORM="kind"
KUBE_CONTEXT="kind-<cluster-name>"       # default: kind-kind
CONTAINER_TOOL="docker"
NEUVECTOR_CRI_RUNTIME="containerd"
NEUVECTOR_CONTAINERD_SOCK="/run/containerd/containerd.sock"
REGISTRY=""                             # local load via `kind load`
```

## Getting the `wheatley` image into the cluster

```bash
docker build -t wheatley-server:latest apps/wheatley
kind load docker-image wheatley-server:latest --name <cluster-name>
```

`push_image` runs `kind load docker-image` automatically when `PLATFORM=kind`.
Set `imagePullPolicy: IfNotPresent` (the default via `$IMAGE_PULL_POLICY`) so the
kubelet doesn't try to pull the locally-loaded tag.

## Notes

- **No ServiceLB and no ingress by default.** `type: LoadBalancer` stays
  `<pending>`. Use `port-forward` for the console (which the walkthroughs do
  anyway). If you want LB, install `cloud-provider-kind` or MetalLB separately.
- NeuVector CRI: kind uses upstream containerd at
  `/run/containerd/containerd.sock` inside the node container — use the
  `containerd.enabled=true` helm path, not the `k3s` one.
- The Enforcer needs the containerd socket and host mounts; on kind these are
  inside the node container and generally just work, but check the Enforcer pod
  logs if Network Activity stays empty.
- Give the Docker VM enough headroom (Docker Desktop: 6–8 GB) or the NeuVector
  control plane will not all schedule.
- Single node ⇒ one Enforcer ⇒ no cross-node segmentation demo. (Add worker
  nodes in the kind config if you specifically want to show that.)
