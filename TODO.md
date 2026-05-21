# FaradAI — Open Items

---

## Ring Assessment 1 — Open Items

Findings from Ring-2.6-1T review (2026-05-20) that survived triage. Ordered by severity.

### Critical

- ~~**[#1] FARADAI_DOCKER_ARGS flag injection**~~ ✓ resolved — allowlist implemented.

### High

- ~~**[#2] Memory validation allows double-unit values**~~ ✓ resolved — anchored regex with decimal support.
- ~~**[#3] Floating base image tag**~~ ✓ resolved — both stages pinned to digest.

### Medium

- **[#6] Fragile container state detection** — `grep -q true` on `docker inspect` output is unanchored; a container in a `restarting` state could match unexpectedly, and `2>/dev/null` swallows daemon errors silently. Fix: `[[ "$(docker inspect --format '{{.State.Running}}' faradai 2>/dev/null)" == "true" ]]`.
- ~~**[#7] No Docker binary pre-flight check**~~ ✓ resolved — `command -v docker` guard added.
- ~~**[#8] entrypoint.sh catch-all silent exit**~~ ✓ resolved — `--help` case added, catch-all prints usage.
- **[#9] uninstall-faradai unguarded sudo** — no `command -v sudo` guard, unlike `install.sh`. Will hang or fail silently on systems requiring a password or missing sudo. Fix: add the same guard `install.sh` uses.

### Low

- **[#11] No `--pull` in build** — `build.sh` reuses cached base layers without checking for upstream updates. Previously accepted as won't-fix; reconsidered.
- **[#13] No Docker daemon availability check** — distinct from #7: Docker installed but daemon stopped produces swallowed socket errors. Fix: `docker info > /dev/null 2>&1 || { echo "faradai: Docker daemon is not running" >&2; exit 1; }`.
- **[#14] No `LABEL` metadata in Dockerfile** — `docker image inspect faradai:latest` yields no provenance. Fix: add OCI labels (`image.title`, `image.source`).
- ~~**[#15] SSH forwarding limitation missing from Troubleshooting**~~ superseded by [#20] — implementing SSH agent forwarding makes the framing moot.
- ~~**[#18] entrypoint.sh help lists host-only `uninstall`**~~ ✓ resolved — removed from in-container help.

---

## GPT-5.5 Review — Open Items

Findings from GPT-5.5 review (2026-05-21) that survived triage. Ordered by severity.

### Critical

- ~~**[#19] CI YAML / branch targeting broken**~~ ✓ resolved — branches corrected to `master`; `uninstall-faradai` added to shellcheck target (it was missing).

### High

- ~~**[#20] SSH agent forwarding not default; `~/.ssh` mounted read-only**~~ ✓ resolved — agent forwarding on by default (`FARADAI_ENABLE_SSH_AGENT:-1`); `~/.ssh` dir mount is opt-in via `FARADAI_MOUNT_SSH_DIR=1`; `known_hosts` pre-seeded in image; README host-agent setup section added. "Known issues" entry moot (section not yet created).
- **[#21] Global `~/.claude` mounted read-write into container** — mounts Claude settings, memory, conversation history, and hooks. Gives the agent access to more than auth, and bleeds global state across projects. Fix: default to an isolated `~/.config/faradai/claude` directory; mount that instead.
- **[#22] Global `~/.aider.conf.yml` mounted read-only** — honest but not ideal; OpenRouter key is still agent-readable. Fix: default to a FaradAI-specific aider config at `~/.config/faradai/aider.conf.yml`; only mount it when `aider` is the active command. Document: use a FaradAI-specific OpenRouter key with a hard cost limit.

### Medium

- **[#23] No `FARADAI_WORKDIR` existence validation** — if the directory is absent or wrong, Docker silently creates or exposes an unexpected path. Fix: `[ -d "${FARADAI_WORKDIR}" ] || { echo "faradai: FARADAI_WORKDIR does not exist: ${FARADAI_WORKDIR}" >&2; exit 1; }`; optionally `realpath` before mounting.
- **[#24] CPU/PID validation accepts zero** — `FARADAI_CPUS=0` and `FARADAI_PIDS=0` pass current validation even though both are nonsensical. Fix: require `FARADAI_CPUS > 0` (using `awk` for float comparison) and `FARADAI_PIDS >= 1` (integer check with `(( FARADAI_PIDS < 1 ))`).
- **[#25] `--publish`/`--device` not gated within allowlist** — current allowlist (#1 fix) permits these, but both widen container boundaries meaningfully (`--device` opens hardware, `--publish` exposes services). Fix: require explicit opt-in via `FARADAI_ALLOW_PUBLISH=1` and `FARADAI_ALLOW_DEVICE=1`; update allowlist enforcement and error message accordingly.

### Low

- **[#26] No `--init` flag on `docker run`** — AI tooling spawns subprocesses; without `--init`, zombie processes accumulate in the long-lived container. Fix: add `--init` to the `docker run` invocation.
- **[#27] No selectable network modes** — default open egress is correct for usefulness, but offline review/refactor/sensitive-client sessions benefit from `--network none`. Fix: add `FARADAI_NETWORK_MODE=open|none` with validation; default `open`. (`broker` mode deferred to v2 — see [#32].)
- **[#28] `faradai update` docs/behavior mismatch** — README says "pulls the latest release"; script clones via SSH, which assumes GitHub SSH auth and implies "master HEAD" not a tagged release. Fix: either correct the README to say "clones latest source," or make it release-based. For public-user friendliness, prefer HTTPS clone over SSH.

---

## Hardening (deferred)

- **Container/image prune mechanism** — add a `faradai prune` subcommand (or note in README) to clean up old images, stopped containers, and orphaned volumes.
- **Known issues / limitations section in README** — document: Docker filesystem I/O overhead, no GPU passthrough, local LSP limitations, multi-user `docker rm` behavior. (Remove "no SSH agent forwarding" entry when [#20] ships.)
- **[#29] Read-only root filesystem opt-in** — writable rootfs allows mutation inside the container; `--read-only` reduces this surface. Fix: add `FARADAI_READ_ONLY_ROOT=1` opt-in with `--tmpfs /tmp` and `--tmpfs ~/.cache` writable mounts. Dogfood before considering as default.

---

## v2 (deferred)

Architectural work beyond v1 scope. Do not pull into v1.

- **[#30] Credential broker / proxy** — agent container should never receive reusable provider keys. Better shape: a sidecar broker owns keys, injects `Authorization` headers, enforces model allowlist and budget limits, logs usage. Agent container talks only to broker. Start with OpenRouter/aider as the simplest path.
- **[#31] Per-project policy / config** — support `.faradai/config` and `.faradai/policy` per project for settings like `network_mode`, `allow_ssh_agent`, `allow_publish`, `provider_profile`. Turns FaradAI from a personal script into a policy-bearing tool.
- **[#32] Broker network mode** — `FARADAI_NETWORK_MODE=broker`: agent container talks only to the broker and approved package/doc endpoints. Requires [#30] to exist first.

---

## Pre-open-source (deferred)

CONTRIBUTING.md ✓, GitHub issue/PR templates ✓, CI pipeline ✓. Future considerations if a community grows: code of conduct enforcement process, security disclosure policy, release tagging strategy.

---

## Explicitly not prioritized

- **Custom seccomp / AppArmor profiles** — extra syscall confinement would help, but is a maintenance thicket. The current baseline (non-root user, `--cap-drop ALL`, `no-new-privileges`, no Docker socket, resource limits) already covers the high-value surface. Revisit after v2 settles.
