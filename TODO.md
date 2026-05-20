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
- **[#15] SSH forwarding limitation missing from Troubleshooting** — documented in Mounts prose but not where users look first. Fix: add a Troubleshooting entry.
- ~~**[#18] entrypoint.sh help lists host-only `uninstall`**~~ ✓ resolved — removed from in-container help.

---

## Hardening (deferred)

- **Container/image prune mechanism** — add a `faradai prune` subcommand (or note in README) to clean up old images, stopped containers, and orphaned volumes.
- **Known issues / limitations section in README** — document: Docker filesystem I/O overhead, no GPU passthrough, no SSH agent forwarding, local LSP limitations, multi-user `docker rm` behavior.

---

## Pre-open-source (deferred)

CONTRIBUTING.md ✓, GitHub issue/PR templates ✓, CI pipeline ✓. Future considerations if a community grows: code of conduct enforcement process, security disclosure policy, release tagging strategy.
