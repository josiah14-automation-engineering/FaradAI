# FaradAI — Open Items

---

## Medium

- ~~**[#43] Use `pwd` as default workdir, project-scoped container naming, trust prompt**~~ ✓ resolved — see BUILDLOG Session 26. — current default (`~/Development/personal`) is hardcoded to one user's layout. Change to `$(pwd)`; add a "mount \<path\> into container? [y/N]" trust prompt before `docker run` (bypass via `FARADAI_TRUST_DIR=1`; skip on attach path). Container names become `faradai-{suffix}` where suffix is derived from `basename $FARADAI_WORKDIR` (sanitized); `FARADAI_NAME=foo` overrides the suffix — user supplies the suffix only, `faradai-` prefix always enforced. Different projects get separate containers automatically; `FARADAI_NAME` is the escape hatch for basename collisions or parallel instances. Drop the Dockerfile `ARG WORKDIR_PATH` mkdir; replace with runtime `mkdir -p`. Thread the dynamic container name through all `docker rm`, `docker exec`, and trap calls. Update `uninstall-faradai` to remove all `faradai-*` containers. Update README env var table: regroup by category and add missing vars (`FARADAI_ENABLE_SSH_AGENT`, `FARADAI_MOUNT_SSH_DIR`, `FARADAI_ALLOW_DEVICE`, `FARADAI_ALLOW_PUBLISH`, `FARADAI_NAME`, `FARADAI_TRUST_DIR`).

- ~~**[#6] Fragile container state detection**~~ ✓ resolved — replaced `grep -q true` with `[[ "$(docker inspect ...)" == "true" ]]` during script refactor.
- **[#9] uninstall-faradai unguarded sudo** — no `command -v sudo` guard, unlike `install.sh`. Will hang or fail silently on systems requiring a password or missing sudo. Fix: add the same guard `install.sh` uses.
- **[#23] No `FARADAI_WORKDIR` existence validation** — if the directory is absent or wrong, Docker silently creates or exposes an unexpected path. Fix: `[ -d "${FARADAI_WORKDIR}" ] || { echo "faradai: FARADAI_WORKDIR does not exist: ${FARADAI_WORKDIR}" >&2; exit 1; }`; optionally `realpath` before mounting.
- **[#24] CPU/PID validation accepts zero** — `FARADAI_CPUS=0` and `FARADAI_PIDS=0` pass current validation even though both are nonsensical. Fix: require `FARADAI_CPUS > 0` (using `awk` for float comparison) and `FARADAI_PIDS >= 1` (integer check with `(( FARADAI_PIDS < 1 ))`).
- ~~**[#25] `--publish`/`--device` not gated within allowlist**~~ ✓ resolved — both removed from base allowlist; require explicit `FARADAI_ALLOW_DEVICE=1` / `FARADAI_ALLOW_PUBLISH=1` opt-in.
- **[#37] No image pre-flight check** — if `faradai:latest` doesn't exist (fresh install before first build, or after `docker image prune`), `docker run` fails with a cryptic Docker error. Distinct from the binary check (#7) and daemon check (#13). Fix: `docker image inspect faradai:latest > /dev/null 2>&1 || { echo "faradai: image not found — run './install.sh' to build it" >&2; exit 1; }`.
- ~~**[#38] entrypoint.sh: args after command silently dropped**~~ ✓ resolved — `"${@:2}"` added to all three exec calls.
- **[#41] faradai update uses SSH clone** — `git clone git@github.com:...` fails for any user without GitHub SSH key auth. Also: after install completes the old case fell through to `docker run` rather than exiting or restarting — replace the entire update block. See also [#28] (README/behavior mismatch). Fix: switch to HTTPS clone; add explicit exit or auto-restart after successful install.

---

## Low

- **[#11] No `--pull` in build** — `build.sh` reuses cached base layers without checking for upstream updates. Previously accepted as won't-fix; reconsidered.
- **[#13] No Docker daemon availability check** — distinct from #7: Docker installed but daemon stopped produces swallowed socket errors. Fix: `docker info > /dev/null 2>&1 || { echo "faradai: Docker daemon is not running" >&2; exit 1; }`.
- **[#14] No `LABEL` metadata in Dockerfile** — `docker image inspect faradai:latest` yields no provenance. Fix: add OCI labels (`image.title`, `image.source`).
- **[#26] No `--init` flag on `docker run`** — AI tooling spawns subprocesses; without `--init`, zombie processes accumulate in the long-lived container. Fix: add `--init` to the `docker run` invocation.
- **[#27] No selectable network modes** — default open egress is correct for usefulness, but offline review/refactor/sensitive-client sessions benefit from `--network none`. Fix: add `FARADAI_NETWORK_MODE=open|none` with validation; default `open`. (`broker` mode deferred to v2 — see [#32].)
- **[#28] `faradai update` docs/behavior mismatch** — README says "pulls the latest release"; script clones master HEAD via SSH. Fix handled by [#41]; this item tracks the README correction once [#41] ships.
- **[#33] `gh auth` credentials not persisted across container restarts** — `gh auth login` stores tokens inside the container's writable layer; lost on rebuild/restart. Fix: mount a host-side `~/.config/gh/` to persist `gh` auth without re-authenticating each session.
- **[#44] Add bats unit tests for validation and flag-parsing logic** — `_validate_memory/cpus/pids`, `_build_extra_docker_args` allowlist, and the `-n`/`-a` flag parser (mutual exclusivity, known-command disambiguation). Docker interaction is out of scope — CI smoke test covers that. Use bats-core; mock external commands via `test/helpers/` bin on `$PATH`; add a CI job.
- **[#39] No logs/status subcommands** — users must shell out to `docker logs faradai` and `docker inspect` for basic diagnostics. Add `faradai logs` and `faradai status`.
- **[#40] No version subcommand** — no `faradai version` or `--version`; no way to verify which CLI is installed without reading the script.
- **[#42] CI smoke test bypasses entrypoint.sh** — build job uses `--entrypoint /bin/bash`, so `entrypoint.sh` is never exercised by CI. Fix: add a step using `docker run --rm faradai:ci claude --version` and `docker run --rm faradai:ci aider --version` through the real entrypoint.

---

## Optional / Future: Strict Profile

The v1 default is optimized for **personal/FOSS development convenience**: writable global `~/.claude`, read-only `~/.aider.conf.yml`, SSH agent forwarding, open network. This is a deliberate tradeoff, not an oversight. For users with a low-capped API key, passphrase-protected SSH keys, and no client/private code in the container, the current mounts are not reckless.

A future `FARADAI_PROFILE=strict` mode should address these for **client/sensitive/mixed-sensitivity work**:

- **[#21] Isolated Claude config** — the global `~/.claude` mount gives the agent access to settings, memory, hooks, and history for all projects. A strict profile should mount an isolated `~/.config/faradai/claude` instead, so container activity does not bleed into the user's global Claude state.
- **[#22] Isolated aider config** — the current `~/.aider.conf.yml` mount is acceptable for a low-budget OpenRouter key. A strict profile should use a dedicated `~/.config/faradai/aider.conf.yml` (or a credential broker — see v2). The `:ro` mount is write-protection, not secrecy; the agent can still read the file if directed to.

Eventual shape:

```bash
FARADAI_PROFILE="${FARADAI_PROFILE:-personal}"
# personal: global ~/.claude rw, ~/.aider.conf.yml ro, SSH agent, open network
# strict:   isolated ~/.config/faradai/claude, isolated aider config, optional network none
```

`strict` consolidates the network-none mode (`FARADAI_NETWORK_MODE=none`) and the read-only root opt-in (`[#29]`) under one profile flag. The credential broker (v2 [#30]) is the long-term answer for the key-readability problem.

---

## Hardening (deferred)

- **Container/image prune mechanism** — add a `faradai prune` subcommand (or note in README) to clean up old images, stopped containers, and orphaned volumes.
- **Known issues / limitations section in README** — document: Docker filesystem I/O overhead, no GPU passthrough, local LSP limitations, multi-user `docker rm` behavior.
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
