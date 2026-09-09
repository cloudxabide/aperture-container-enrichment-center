# Platform notes — minikube

## `env.sh` values

```bash
PLATFORM="minikube"
KUBE_CONTEXT="minikube"
CONTAINER_TOOL="docker"
# CRI depends on how you started minikube:
#   --container-runtime=containerd  ->  containerd, /run/containerd/containerd.sock
#   --container-runtime=docker      ->  docker
NEUVECTOR_CRI_RUNTIME="containerd"
NEUVECTOR_CONTAINERD_SOCK="/run/containerd/containerd.sock"
REGISTRY=""
```

Start with enough resources:

```bash
minikube start --cpus=4 --memory=8g --container-runtime=containerd
```

## Getting the `wheatley` image into the cluster

```bash
docker build -t wheatley-server:latest apps/wheatley
minikube image load wheatley-server:latest
```

`push_image` runs `minikube image load` automatically when `PLATFORM=minikube`.
Alternative: `eval $(minikube docker-env)` before building so the image lands in
minikube's daemon directly.

## Notes

- `minikube tunnel` provides `LoadBalancer` addresses; `minikube service` opens
  NodePort services. The walkthroughs use `port-forward` regardless.
- Match `NEUVECTOR_CRI_RUNTIME` / `NEUVECTOR_CONTAINERD_SOCK` to the
  `--container-runtime` you started with. The `docker` driver + `docker` runtime
  needs the `docker.enabled=true` helm path instead.
- Some minikube drivers (e.g. `docker` on macOS) nest the node in a container;
  the Enforcer's host mounts still resolve, but verify the pod is `Running` and
  check its logs.
- Single node ⇒ one Enforcer ⇒ no cross-node segmentation demo (`minikube
  node add` if you need it).
