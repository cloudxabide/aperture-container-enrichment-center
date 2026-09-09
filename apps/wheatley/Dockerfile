# wheatley — multi-stage build to a true distroless image.
#
#   builder : full Go toolchain, produces one static binary
#   final   : gcr.io/distroless/static-debian12:nonroot
#             no shell, no package manager, no coreutils, non-root by default
#
# Build via Scripts/31_deploy_distroless.sh (which routes through
# build_image / push_image in Scripts/lib/common.sh for the current $PLATFORM).
# Manual equivalent:
#   nerdctl --namespace k8s.io build -t wheatley-server:latest apps/wheatley

# ── builder stage ────────────────────────────────────────────────────────────
FROM golang:1.22-alpine AS build
WORKDIR /src

# Populated automatically by BuildKit/nerdctl; default to the build host's arch
# so a native build on Apple Silicon (arm64) produces an arm64 binary.
ARG TARGETOS=linux
ARG TARGETARCH

# No third-party deps — copy the module files first for layer caching, then src.
COPY go.mod ./
COPY main.go ./

# CGO off + netgo/osusergo => a fully static binary that runs on scratch/distroless.
RUN CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -ldflags="-s -w" -tags netgo,osusergo \
    -o /out/wheatley-server .

# ── final stage — true distroless ───────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/wheatley-server /wheatley-server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/wheatley-server"]
