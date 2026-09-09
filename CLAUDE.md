# CLAUDE.md

Guidance for AI agents (and humans) working in this repo.

## What this is

A hands-on demo of **SUSE Security (NeuVector) 5.x** on a single-node Kubernetes
cluster. Built and tested on **Rancher Desktop**; written to run on any
single-node cluster with the Rancher-specific bits isolated behind a `$PLATFORM`
switch.

The authoritative plan — thesis, test chambers, decisions — is
[`docs/PLAN.md`](docs/PLAN.md). Read it before changing scope.

## Repo layout

| Path | Contents |
|------|----------|
| `Project.md` | One-paragraph charter. Keep it short. |
| `docs/PLAN.md` | The working plan. Update it when scope changes. |
| `docs/00-glossary.md` | Canonical term definitions. |
| `docs/10-setup.md` | Cluster + NeuVector install, platform-agnostic. |
| `docs/Security_Demo*.md`, `docs/Security_Discussion.md` | The walkthroughs. |
| `docs/platform-notes/` | One file per platform; `rancher-desktop.md` is the only Rancher-specific doc. |
| `Files/env.sh.example` | Committed template. Users copy to `./env.sh` at the repo root (git-ignored). |
| `Files/` | Landing zone for loose reference files that don't belong elsewhere. |
| `Scripts/` | Numbered, ordered scripts (`NN_verb_noun.sh`) + `lib/common.sh`. |
| `Scripts/lib/common.sh` | Shared shell helpers. Every script sources it. |
| `manifests/` | Kubernetes YAML, grouped by namespace. |
| `apps/` | Source for images we build (currently `wheatley`). |
| `.claude/skills/add-chamber/` | Skill: scaffold a new test chamber. |

## Conventions

### Shell scripts
- Start with `#!/usr/bin/env bash`, then `set -euo pipefail`, then source
  `lib/common.sh`:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
  ```
- Filenames: `NN_verb_noun.sh`, two-digit prefix giving run order
  (`00_preflight`, `10_install_neuvector`, `20_expose_console`, `30_deploy_apps`,
  `31_deploy_distroless`, `40_attack_fat`, `90_reset_demo`).
- Never call `kubectl` directly — call `kube` (from `common.sh`) so
  `$KUBE_CONTEXT` is honoured.
- Never hard-code anything that belongs in `env.sh` (namespaces, image refs,
  versions, URLs, ports). Read it from the sourced environment.
- Use `info` / `warn` / `die` for output, not bare `echo`.
- Keep scripts idempotent — safe to re-run.
- Lint before committing: `shellcheck -x Scripts/**/*.sh`.
- Call `helm` via `helm_cmd` (from `common.sh`) so `$KUBE_CONTEXT` is honoured.

### Manifests
- Files in `manifests/` carry `${VAR}` placeholders for anything from `env.sh`
  (namespaces, image refs, pull policy, test parameters) — never literal values.
- Deploy scripts render them with `render_manifest <file> VAR VAR … | kube apply -f -`
  (a `envsubst` safelist wrapper in `common.sh`). Requires `envsubst` on PATH.
- `manifests/00-namespaces.yaml` is applied (idempotently) by every deploy script.

### Naming (important)
Real Kubernetes objects use plain names; the Portal / GLaDOS names are
**narrative aliases used only in prose**.

| Real object | Prose alias |
|-------------|-------------|
| `chell-test` (Deployment, `aperture-sci`) | "the weighted companion pod" / clean app |
| `wheatley` (Deployment, `aperture-labs`) | the distroless app |
| Protect mode | "glados-enforcer-mode" |
| NeuVector Enforcer | "dpi-sentry-turret" |

Do not create Kubernetes/NeuVector objects named after the aliases.

### Platform-specific code
Anything that differs by cluster (image load, containerd socket, context name,
console exposure) goes **behind the `$PLATFORM` switch in `env.sh` /
`common.sh`**, or gets an explicit **"Rancher Desktop only"** callout in the
docs. The walkthrough steps themselves stay platform-neutral — standardise on
`kubectl port-forward` for console access.

### Walkthrough doc house style
- Sections in this order: `Status` → `Overview` → `The Setup` → numbered `Part`s
  → `Demo Summary` (a table) → `Key Takeaways` → `References`.
- Presenter cues use a blockquote with a target emoji:
  `> 🎯 **Key talking point:** …`
- Show expected output in fenced blocks immediately after the command.
- Every walkthrough ends with a `Demo Summary` table: `Action | Mode | Result`.
- Link sibling docs by relative path.

## Common commands

```bash
cp Files/env.sh.example env.sh      # first-time setup, then edit env.sh
Scripts/00_preflight.sh            # verify cluster reachable, tools present
Scripts/10_install_neuvector.sh   # helm install NeuVector
Scripts/20_expose_console.sh      # port-forward the NeuVector console
Scripts/30_deploy_apps.sh         # deploy chell-test into aperture-sci
Scripts/31_deploy_distroless.sh   # build + load + deploy wheatley into aperture-labs
Scripts/90_reset_demo.sh          # tear down demo namespaces
```

## Don't

- Don't commit `env.sh` (it may hold a registry path or credentials).
- Don't add a skill or abstraction until the pattern has repeated — see
  `docs/PLAN.md` §2 for what was deliberately deferred.
- Don't expand scope (new chambers, admission control, multi-node) without
  updating `docs/PLAN.md` first.
