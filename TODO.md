# FaradAI — Open Items

---

## Medium

- ~~**[#43] Use `pwd` as default workdir, project-scoped container naming, trust prompt**~~ ✓ resolved — see BUILDLOG Sessions 26–27.

- ~~**[#6] Fragile container state detection**~~ ✓ resolved — replaced `grep -q true` with `[[ "$(docker inspect ...)" == "true" ]]` during script refactor.
- ~~**[#9] uninstall-faradai unguarded sudo**~~ ✓ resolved — `command -v sudo` guard added matching `install.sh`; commit f4c80c8.
- ~~**[#23] No `FARADAI_WORKDIR` existence validation**~~ ✓ resolved — existence check added after workdir resolution; commit f4c80c8.
- ~~**[#24] CPU/PID validation accepts zero**~~ ✓ resolved — `_validate_cpus` rejects zero via awk float comparison; `_validate_pids` rejects zero via integer if-block; commit f4c80c8.
- ~~**[#25] `--publish`/`--device` not gated within allowlist**~~ ✓ resolved — both removed from base allowlist; require explicit `FARADAI_ALLOW_DEVICE=1` / `FARADAI_ALLOW_PUBLISH=1` opt-in.
- ~~**[#37] No image pre-flight check**~~ ✓ resolved — `docker image inspect faradai:latest` pre-flight added with clear error directing user to `./install.sh`; commit f4c80c8.
- ~~**[#38] entrypoint.sh: args after command silently dropped**~~ ✓ resolved — `"${@:2}"` added to all three exec calls.
- ~~**[#41] faradai update uses SSH clone**~~ ✓ resolved — switched to HTTPS clone; error message updated; see also [#28]. Commit in Session 30.

---

## Low

- ~~**[#11] No `--pull` in build**~~ ✓ resolved — `--pull` added to `docker build` in `build.sh`. See BUILDLOG Session 33.
- ~~**[#13] No Docker daemon availability check**~~ ✓ resolved — `docker info` pre-flight added after binary check; commit in Session 30.
- ~~**[#14] No `LABEL` metadata in Dockerfile**~~ ✓ resolved — OCI `image.title` and `image.source` labels added to final stage; commit in Session 30.
- ~~**[#26] No `--init` flag on `docker run`**~~ ✓ resolved — `--init` added to `docker run`; commit in Session 30.
- ~~**[#27] No selectable network modes**~~ ✓ resolved — `FARADAI_NETWORK_MODE=open|none` added with validation; default `open`; `none` passes `--network none` to `docker run`. `broker` mode remains deferred to v2 (see [#32]). See BUILDLOG Session 32.
- ~~**[#28] `faradai update` docs/behavior mismatch**~~ ✓ resolved — README corrected alongside [#41]. Commit in Session 30.
- ~~**[#33] `gh auth` credentials not persisted across container restarts**~~ ✓ resolved — `~/.config/gh/` now mounted read-write; host dir created with `mkdir -p` if absent. See BUILDLOG Session 32.
- **[#45] Migrate complex Bash scripting to Rash** — flag parser, `_validate_*` functions, and `_build_extra_docker_args` are the most Bash-hostile sections. Rash (Racket-hosted shell DSL) would provide real data types, proper error handling, and macros for eliminating repetition. Deferred until v1 feature set stabilizes; adds a Racket dependency to the Dockerfile. See BUILDLOG Session 25 for stay-in-Bash reasoning. GitHub #40.
- **[#44] Add bats unit tests for validation and flag-parsing logic** — `_validate_memory/cpus/pids`, `_build_extra_docker_args` allowlist, and the `-n`/`-a` flag parser (mutual exclusivity, known-command disambiguation). Docker interaction is out of scope — CI smoke test covers that. Use bats-core; mock external commands via `test/helpers/` bin on `$PATH`; add a CI job.
- **[#46] `ssh-add -l` in smoketest exposes key fingerprints and email labels** — replace with `ssh-add -l | wc -l` (or `ssh-add -l > /dev/null && echo "keys loaded"`) to confirm forwarding works without printing identity metadata into the conversation context.
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
