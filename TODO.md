# FaradAI — Open Items

All planned items complete. See Pre-open-source scaffolding below if the project grows.

---

## Pre-open-source (deferred)

CONTRIBUTING.md ✓, GitHub issue/PR templates ✓, CI pipeline ✓. Future considerations if a community grows: code of conduct enforcement process, security disclosure policy, release tagging strategy.

---

## Hardening (deferred)

- **Image digest pinning** — pin `ubuntu:24.04` to a specific digest (`@sha256:...`) in `Dockerfile` for true build reproducibility. Low priority until the project needs reproducible releases.
- **Container/image prune mechanism** — add a `faradai prune` subcommand (or note in README) to clean up old images, stopped containers, and orphaned volumes.
- **Known issues / limitations section in README** — document: Docker filesystem I/O overhead, no GPU passthrough, no SSH agent forwarding, local LSP limitations, multi-user `docker rm` behavior.
