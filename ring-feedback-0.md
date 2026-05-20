# Ring Feedback — FaradAI Project (Assessment 0)

Ring-2.6-1T critique via aider — 2026-05-20. Files reviewed: `Dockerfile`, `faradai`, `entrypoint.sh`, `build.sh`, `install.sh`, `README.md`, `CLAUDE.md`.

---

## Summary Table

| # | Severity | Category | Finding |
|---|----------|----------|---------|
| 1 | HIGH | Security | Container runs with default capabilities, no seccomp, no cap-drop |
| 2 | HIGH | Design | Non-atomic container create/exec lifecycle |
| 3 | MEDIUM | Security | ENV variables interpolated into docker flags without validation |
| 4 | MEDIUM | Security | `--network=host` during build |
| 5 | MEDIUM | Security | No image pinning or signing |
| 6 | MEDIUM | Security | API key readable inside container despite `:ro` mount |
| 7 | MEDIUM | Design | Hardcoded paths not configurable |
| 8 | MEDIUM | Design | Builder stage not cleaned, cache files copied to final image |
| 9 | MEDIUM | Design | `|| true` masks real failures in Dockerfile |
| 10 | MEDIUM | Feature | No update/upgrade mechanism |
| 11 | MEDIUM | Feature | No logging or debugging support |
| 12 | MEDIUM | Feature | No way to pass custom Docker flags |
| 13 | MEDIUM | Docs | No troubleshooting section |
| 14 | MEDIUM | Docs | No upgrade/update instructions |
| 15 | LOW | Security | `install.sh` uses `sudo` without verification |
| 16 | LOW | Security | `docker rm -f` can affect other users' containers |
| 17 | LOW | Feature | No uninstall, no prune, no cleanup |
| 18 | LOW | Docs | No known issues, limitations, or contribution guide |
| 19 | LOW | Code | `install.sh` missing `set -euo pipefail` |

---

## 1. Security Issues

**[HIGH] Container runs with default Docker capabilities**
The `docker run` command in `faradai` does not drop capabilities or apply a restricted seccomp profile. By default Docker grants containers ~14 Linux capabilities including `NET_RAW`, `SYS_CHROOT`, etc. A compromised process inside the container has more privilege than it needs. Recommendation: add `--cap-drop ALL` and `--security-opt no-new-privileges` to the `docker run` invocation.

**[MEDIUM] Environment variable injection in `faradai` script**
`FARADAI_MEMORY`, `FARADAI_CPUS`, and `FARADAI_PIDS` are interpolated directly into `docker run` flags with no validation. While `${}` quoting prevents word splitting, the lack of input validation (e.g., a regex check for `[0-9]+[kmg]?`) is sloppy and could mask misconfiguration.

**[MEDIUM] `--network=host` during build**
`build.sh` uses `--network=host`, giving the build process full access to the host's network stack. Any `RUN` instruction (e.g., a compromised package mirror during `apt-get`) can reach host-local services. The README explains this correctly but doesn't flag the build-time risk specifically.

**[MEDIUM] No image verification or pinning**
The image is tagged `faradai:latest` with no content-addressable pinning (digest), no image signing, and no verification step. If the image is ever pulled from a registry or a MITM attack occurs, arbitrary code could run with the user's UID/GID and access to mounted credentials.

**[MEDIUM] API key readable inside container despite `:ro` mount**
The `:ro` overlay on `~/.aider.conf.yml` prevents writes, but any process in the container can `cat` the file and exfiltrate the OpenRouter API key. The README acknowledges this but the `:ro` designation gives a false sense of security. Cost-limited key is the only real mitigation.

**[LOW] `install.sh` uses `sudo` without checking for it**
If `sudo` is unavailable or the user lacks privileges, the script fails with an unhelpful error. There is no checksum or signature verification — `sudo install` copies whatever is at the path into `/usr/local/bin/`.

**[LOW] `docker rm -f faradai` can kill containers from other users**
On a multi-user system, the `docker rm -f faradai` in the `faradai` script will destroy any stopped container named `faradai` regardless of owner. Minor denial-of-service vector on shared machines.

---

## 2. Design Flaws

**[HIGH] Container creation and exec are not atomic**
The `faradai` script runs `docker rm -f` then `docker run`. If the script is killed between those two steps, or if `docker run` fails mid-way, a stale or missing container remains. There is no cleanup trap, no lock, and no state check beyond the single `docker inspect` call.

**[MEDIUM] Hardcoded paths are not configurable**
`~/Development/personal` is hardcoded in three places: `faradai` (mount + workdir), `Dockerfile` (directory creation), and implicitly in `entrypoint.sh` via WORKDIR. Users who want a different project directory must edit multiple files. This should be an environment variable.

**[MEDIUM] Builder stage cache files copied to final image**
The builder stage installs `pipx`, `nodejs`, `npm`, `python3-pip`, and `python3-venv`. The `pipx install` creates a venv that includes pip, setuptools, and wheel — none needed at runtime. The final image copies the entire `~/.local` directory including cache files. No cleanup of the builder stage is performed.

**[MEDIUM] `|| true` masks real failures**
Used in `docker rm -f faradai 2>/dev/null || true` (acceptable) and `apt-get purge -y --auto-remove sudo 2>/dev/null || true` (concerning). If `apt-get purge` fails for a real reason (e.g., locked dpkg), the build continues silently.

**[LOW] No health check**
The Dockerfile has no `HEALTHCHECK`. If the container hangs or the agent process dies silently, `docker inspect` reports it as running but it's non-functional. Users get no diagnostic information.

---

## 3. Missing Features

**[MEDIUM] No update/upgrade mechanism**
No `faradai update` command, no way to rebuild and replace the running container gracefully, no version tracking. Users must manually re-run `build.sh`.

**[MEDIUM] No logging or debugging support**
The `faradai` script produces no logs. If `docker run` fails, the error is dumped to stderr with no context. No `--verbose` or `--debug` flag.

**[MEDIUM] No way to pass custom Docker flags**
Users cannot add volume mounts, environment variables, or port mappings without editing the `faradai` script. A `FARADAI_DOCKER_ARGS` environment variable or similar escape hatch would allow customization without forking.

**[LOW] No uninstall command**
`install.sh` has no counterpart. Users must manually remove `/usr/local/bin/faradai` and the Docker image.

**[LOW] No container prune/cleanup**
No mechanism to clean up old images, stopped containers, or orphaned volumes. Disk space accumulates over time.

**[LOW] `entrypoint.sh` has no extension mechanism**
The README notes the container pattern is extensible, but `entrypoint.sh` has no plugin mechanism. Adding a new mode requires editing the Dockerfile and entrypoint.

---

## 4. Documentation Gaps

**[MEDIUM] No troubleshooting section**
Common issues (Docker permission denied, port conflicts, credential errors, SSH forwarding limitations) are not addressed anywhere in the README.

**[MEDIUM] No upgrade/update instructions**
Users with an existing installation have no documented path to update the image or the CLI script.

**[MEDIUM] `~/.claude.json` mount is read-write with no explanation**
The mount table shows it as read-write but doesn't explain what this file is, whether it's sensitive, or whether changes persist across rebuilds.

**[LOW] No known issues / limitations section**
No mention of: performance overhead of Docker, filesystem I/O penalties, no GPU passthrough, inability to use local LSPs that require host paths, etc.

**[LOW] No contribution guidelines**
README mentions "Contributions welcome if there is demand" but no `CONTRIBUTING.md`, no code of conduct, no issue templates.

---

## 5. File-Specific Notes

**`faradai` script**: The `exec docker exec -it faradai "${@:-bash}"` attach path does not verify that the running container was started with the current script version or configuration. If the container was started with an old `faradai` script, the exec lands in a stale environment silently.

**`Dockerfile`**: `ARG USERNAME` is used in the builder stage for paths but the user is never actually created there — it relies on root running as the effective user. This is correct but undocumented, which makes the builder stage confusing to read.

**`entrypoint.sh`**: The `claude` case runs `exec claude` with no arguments passed through. `faradai --help` would invoke `claude --help`, which may or may not be intended. No `--version` flag.

**`install.sh`**: Alone among all scripts in the project, it lacks `set -euo pipefail`. A failure mid-install could leave a partial or corrupt binary at `/usr/local/bin/faradai`.

---

*Tokens: 4.5k sent, 3.6k received. Cost: $0.0026.*

---

## Resolutions

| # | Status | Notes |
|---|--------|-------|
| 1 | Resolved — 2026-05-20 | `--cap-drop ALL` and `--security-opt no-new-privileges` added to `docker run` in `faradai`. |
| 2 | Resolved — 2026-05-20 | `trap 'docker rm -f faradai ...' INT TERM EXIT` added after the `docker rm -f` line; only active in the window before `exec docker run` replaces the shell. |
| 7 | Resolved — 2026-05-20 | `FARADAI_WORKDIR` env var (default `${HOME}/Development/personal`) threads through `faradai`, `Dockerfile` (`ARG WORKDIR_PATH`), and `build.sh`. `entrypoint.sh` had no hardcoded paths. |
| 8 | Resolved — 2026-05-20 | Builder stage cleans pip cache (`pipx runpip cache purge`), npm cache, `__pycache__` dirs, and `~/.cache`. pip/setuptools/wheel left in venv to avoid breaking runtime installs. |
| 13 | Resolved — 2026-05-20 | Troubleshooting section added to README: Docker permission denied, expired credentials, container name conflict, SSH key permissions, aider not found, wrong model slug. |
| 14 | Resolved — 2026-05-20 | Upgrading section added to README: git pull → build.sh → install.sh workflow, running container note, pinned version update instructions. |
| 12 | Resolved — 2026-05-20 | `FARADAI_DOCKER_ARGS` env var word-split into `EXTRA_DOCKER_ARGS` array and appended to `docker run`. Paths with spaces not supported. |
| 3 | Resolved — 2026-05-20 | Validation added for `FARADAI_MEMORY` (m/g units, 512g ceiling), `FARADAI_CPUS` (decimal-aware, 128-core ceiling), and `FARADAI_PIDS` (positive integer). k-unit excluded as unrealistic. |
| 19 | Stale — 2026-05-20 | `install.sh` already had `set -euo pipefail`. Finding was incorrect. |
| 9 | Resolved — 2026-05-20 | `apt-get purge sudo \|\| true` removed from Dockerfile — sudo is never present in the ubuntu:24.04 Docker image (documented in BUILDLOG Session 8), making this a no-op that could mask real dpkg failures. `userdel`/`groupdel` `\|\| true` retained — genuinely conditional on whether the ubuntu user exists in a given base image version. |
