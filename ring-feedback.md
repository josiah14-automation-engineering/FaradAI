# Ring Feedback — FaradAI Project (Assessment 1)

Ring-2.6-1T critique via aider — 2026-05-20. Files reviewed: `Dockerfile`, `faradai`, `entrypoint.sh`, `build.sh`, `install.sh`, `uninstall-faradai`, `README.md`, `CLAUDE.md`.

---

## Summary Table

| # | Severity | Category | Finding |
|---|----------|----------|---------|
| 1 | CRITICAL | Security — Injection | `FARADAI_DOCKER_ARGS` is word-split and passed raw to `docker run`, allowing arbitrary flag injection (`--privileged`, extra volume mounts, `--network=host`) that completely bypasses the container's security model. |
| 2 | HIGH | Security — Validation | Memory-unit validation strips exactly one trailing character; values like `4mm` or `4gg` pass the regex check but Docker rejects them, producing an unhandled runtime error. |
| 3 | HIGH | Security — Supply Chain | Dockerfile uses floating base-image tag `ubuntu:24.04` with no digest pin; a re-published tag would silently propagate into rebuilt images. |
| 4 | MEDIUM | Security — Network | `build.sh` passes `--network=host` to `docker build`, giving the build container full access to the host's network stack during the `apt-get` phase. |
| 5 | MEDIUM | Security — Secrets | `~/.claude/.credentials.json` is mounted `:ro` as an overlay on a read-write `~/.claude/` mount; the `:ro` prevents writes but not reads — a compromised process can still read the token. |
| 6 | MEDIUM | Security — Input Parsing | `docker inspect --format '{{.State.Running}}'` output is piped to `grep -q true` without anchoring; a container in an unexpected state could produce a partial match. |
| 7 | MEDIUM | Code Quality — Robustness | No pre-flight check for Docker installation; if `docker` is absent, the script fails deep inside the `docker run` call with an unhelpful "command not found". |
| 8 | MEDIUM | Code Quality — Robustness | `entrypoint.sh` `*` catch-all exits with code 1 without printing help text, unlike the `--help` path. |
| 9 | MEDIUM | Code Quality — Portability | `uninstall-faradai` calls `sudo` directly with no guard; on systems where sudo requires a password or is not in PATH, uninstall will fail or hang. |
| 10 | LOW | Security — Debug | `FARADAI_DEBUG=1` enables `set -x`, which echoes all expanded variables (including env secrets) to stderr with no warning. |
| 11 | LOW | Security — Build Hygiene | `build.sh` does not pass `--pull`; stale cached base layers will be reused without checking for upstream updates. |
| 12 | LOW | Security — Build Hygiene | *(Disputed)* Ring flagged no `.dockerignore`; one exists. Finding may reflect stale context. |
| 13 | LOW | Code Quality — UX | `faradai` script does not check Docker daemon availability; a stopped daemon produces confusing cascading failures. |
| 14 | LOW | Code Quality — Maintainability | No `LABEL` metadata in Dockerfile; image provenance is opaque after build. |
| 15 | LOW | Code Quality — Documentation | README Troubleshooting section omits SSH agent forwarding; limitation is only mentioned in the Mounts section prose. |
| 16 | LOW | Code Quality — Tooling | No shell completion (bash/zsh/fish) for the `faradai` CLI despite multiple subcommands. |
| 17 | LOW | Code Quality — Tooling | No `CHANGELOG.md`; given pinned tool versions and an `update` subcommand, a changelog would help users track what changed. |
| 18 | LOW | Code Quality — Consistency | `entrypoint.sh` help text lists `uninstall` as a valid command, but `uninstall` is host-only; running it inside the container produces a "command not found" error. |

---

## Detailed Findings

### 1. Arbitrary Docker Flag Injection via `FARADAI_DOCKER_ARGS` (CRITICAL)

**File:** `faradai`

`FARADAI_DOCKER_ARGS` is word-split into an array and appended to the `docker run` invocation with no allowlist or validation:

```bash
EXTRA_DOCKER_ARGS=()
if [[ -n "${FARADAI_DOCKER_ARGS:-}" ]]; then
  read -ra EXTRA_DOCKER_ARGS <<< "${FARADAI_DOCKER_ARGS}"
fi
# ...
"${EXTRA_DOCKER_ARGS[@]}" \
```

This allows an attacker or careless user to inject any Docker flag, including:

- `--privileged` — grants all Linux capabilities, completely defeating `--cap-drop ALL`.
- `--cap-add SYS_ADMIN` — allows mounting filesystems, enabling container escape.
- `-v /etc/shadow:/etc/shadow` — mounts sensitive host files into the container.
- `--network=host` — exposes the host network stack.
- `--pid=host` — allows viewing and killing host processes.

The entire security model described in `CLAUDE.md` and `README.md` can be undone with a single environment variable.

**Recommendation:** Either remove `FARADAI_DOCKER_ARGS` entirely, or implement an allowlist of safe flags (e.g., only `--env`, `--label`, or `--device`).

---

### 2. Memory Validation Allows Double-Unit Values (HIGH)

**File:** `faradai`

The validation strips exactly one trailing character:

```bash
_mem_val="${FARADAI_MEMORY%[mgMG]}"
_mem_unit="${FARADAI_MEMORY: -1}"
```

For input `4mm`, `_mem_val` becomes `4m` and `_mem_unit` becomes `m` — both pass validation. Docker receives `4mm` and rejects it with an unhelpful error. The same applies to `4gg`, `4MM`, etc.

**Recommendation:** Use a stricter anchored regex: `^[0-9]+(\.[0-9]+)?[mgMG]$`. Alternatively, validate that the stripped value is purely numeric before accepting it.

---

### 3. Floating Base Image Tag (HIGH)

**File:** `Dockerfile`, lines 1 and 22

```dockerfile
FROM ubuntu:24.04 AS builder
# ...
FROM ubuntu:24.04 AS final
```

Neither stage pins a digest. If Canonical re-publishes the `24.04` tag after a security patch, subsequent rebuilds silently pull a different base image. In a supply-chain context this is a risk.

**Recommendation:** Pin to a specific digest: `FROM ubuntu@sha256:<digest> AS builder`.

---

### 4. `--network=host` During Build (MEDIUM)

**File:** `build.sh`

`--network=host` is passed to `docker build` to allow `apt-get` to resolve DNS and reach package repositories. While reasonable for build performance, it means every `RUN` instruction in the Dockerfile has full access to the host's network stack — including local services on `localhost`, dev servers, and cloud metadata endpoints (`169.254.169.254`).

**Recommendation:** Acceptable if understood and documented. Consider `--network=default` with explicit `--dns` flags if only DNS resolution is needed.

---

### 5. Credential Overlay Mount Risk (MEDIUM)

**File:** `faradai`; `README.md`

`~/.claude/` is mounted read-write, and `~/.claude/.credentials.json` is separately overlaid `:ro`. The overlay prevents writes, but a compromised Claude Code process can still:

- Read `.credentials.json` directly.
- Write to other files in `~/.claude/` that may influence Claude Code's behaviour.

The README documents this tradeoff, but the distinction between "`:ro` prevents writes" and "`:ro` does not prevent reads" could be stated more plainly.

---

### 6. Fragile Docker Container State Detection (MEDIUM)

**File:** `faradai`

```bash
if docker inspect --format '{{.State.Running}}' faradai 2>/dev/null | grep -q true; then
```

Problems:
- `grep -q true` matches any line containing the substring `true` — not anchored to `^true$`.
- A container in a `restarting` state may produce unexpected output.
- `2>/dev/null` silently swallows Docker-not-running and permission-denied errors.

**Recommendation:** Compare directly in bash: `[[ "$(docker inspect --format '{{.State.Running}}' faradai 2>/dev/null)" == "true" ]]`.

---

### 7. No Docker Pre-Flight Check (MEDIUM)

**File:** `faradai`

The script calls `docker inspect` and `docker run` without first checking whether the `docker` binary exists and the daemon is reachable. If Docker is not installed or the daemon is stopped, the error surfaces deep inside the script with no actionable message.

**Recommendation:** Add at the top:
```bash
command -v docker > /dev/null 2>&1 || { echo "faradai: Docker is not installed or not in PATH" >&2; exit 1; }
```

---

### 8. `entrypoint.sh` Catch-All Inconsistency (MEDIUM)

**File:** `entrypoint.sh`

The `*` catch-all in the `case` statement exits with code 1 silently, while the `--help` path prints usage text before exiting. An unrecognised command gives the user no guidance.

**Recommendation:** Have the catch-all print the help text before exiting 1, matching the `--help` behaviour.

---

### 9. `uninstall-faradai` Relies on Unguarded `sudo` (MEDIUM)

**File:** `uninstall-faradai`

```bash
sudo rm -f /usr/local/bin/faradai
sudo rm -f /usr/local/bin/uninstall-faradai
```

`install.sh` guards for `sudo` availability at the top; `uninstall-faradai` does not. On systems where sudo requires a password or is not in PATH, uninstall will fail mid-script or hang waiting for input.

**Recommendation:** Add the same `command -v sudo` guard that `install.sh` uses.

---

### 10. Debug Mode Leaks Environment (LOW)

**File:** `faradai`

```bash
if [[ "${FARADAI_DEBUG:-0}" == "1" ]]; then
  echo "faradai: WORKDIR=... MEMORY=... CPUS=... PIDS=..." >&2
  set -x
fi
```

`set -x` echoes every subsequent command with all expanded variables to stderr. If the user has secrets in environment variables (e.g., API keys in the shell profile), those will be printed. No warning is issued.

**Recommendation:** Print a warning when `FARADAI_DEBUG=1` is set: `"faradai: debug mode active — expanded variables will be printed to stderr"`.

---

### 11. No `--pull` in Build (LOW)

**File:** `build.sh`

`docker build` does not include `--pull`, so previously cached base image layers are reused without checking for upstream updates. This could delay the receipt of security patches from the base image.

*(Previously flagged and accepted as won't-fix.)*

---

### 12. No `.dockerignore` — Disputed (LOW)

Ring flagged the absence of a `.dockerignore`. A `.dockerignore` does exist in the project. This finding appears to reflect stale context in Ring's review. No action needed.

---

### 13. No Docker Daemon Availability Check (LOW)

**File:** `faradai`

Distinct from #7 (binary presence): if Docker is installed but the daemon is not running, `docker inspect` and `docker run` fail with socket errors that are swallowed by `2>/dev/null` or produce confusing cascading output.

**Recommendation:** After the binary check, add: `docker info > /dev/null 2>&1 || { echo "faradai: Docker daemon is not running" >&2; exit 1; }`.

---

### 14. No `LABEL` Metadata in Dockerfile (LOW)

**File:** `Dockerfile`

No `LABEL` instructions are present. After building, `docker image inspect faradai:latest` provides no metadata about the maintainer, version, description, or source repository.

**Recommendation:** Add standard OCI labels:
```dockerfile
LABEL org.opencontainers.image.title="FaradAI" \
      org.opencontainers.image.source="https://github.com/josiah14-automation-engineering/faradai"
```

---

### 15. SSH Agent Forwarding Not in Troubleshooting (LOW)

**File:** `README.md`

The SSH agent forwarding limitation is documented in the Mounts section as a blockquote, but not in the Troubleshooting section. Users who hit SSH push/pull failures are likely to check Troubleshooting first and miss the explanation.

**Recommendation:** Add a Troubleshooting entry: "SSH push/pull fails inside the container — SSH agent forwarding is not supported; use HTTPS remotes or an SSH key mount."

---

### 16. No Shell Completion (LOW)

**File:** (missing)

The `faradai` CLI exposes multiple subcommands (`claude`, `aider`, `bash`, `update`, `uninstall`, `help`) but provides no completion scripts for bash, zsh, or fish.

---

### 17. No `CHANGELOG.md` (LOW)

**File:** (missing)

The project pins tool versions (`@anthropic-ai/claude-code@2.1.143`, `aider-chat==0.86.2`) and ships an `update` subcommand, but has no `CHANGELOG.md`. Users cannot determine what changed between versions without reading git history.

---

### 18. `entrypoint.sh` Help Lists Host-Only Command (LOW)

**File:** `entrypoint.sh`

The help text lists `uninstall` as a valid command, but `uninstall` is handled by the host-side `uninstall-faradai` binary, not by `entrypoint.sh`. A user who shells into the container and runs `faradai uninstall` will receive a "command not found" error after the help text suggested it would work.

**Recommendation:** Remove `uninstall` from the `entrypoint.sh` help text, or add a note: `uninstall  (host-only — run outside the container)`.

---

*Tokens: 7.1k sent, 6.3k received. Cost: $0.0045.*
