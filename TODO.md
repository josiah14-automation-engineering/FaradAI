# FaradAI — Open Items

---

## Pre-open-source: multi-stage build

**Priority: do this before publishing. In progress — awaiting build confirmation.**

Move to a multi-stage Dockerfile. Builder stage installs tools as root with `HOME`/`PIPX_HOME`/`PIPX_BIN_DIR` set explicitly; final stage is a clean `ubuntu:24.04` with runtime packages only, copying `~/.local` from the builder.

**Why:** `apt-get purge sudo` writes a whiteout entry — it hides sudo at runtime but doesn't remove it from earlier layers. Anyone who extracts the image tarball and mounts a pre-purge layer gets the binary directly. A multi-stage build ensures the final image's layer history never includes artifacts from the build process.

**Honest note:** `ubuntu:24.04` the Docker image doesn't actually ship with sudo — the purge was always defensive. The real win here is layer hygiene and clean separation of build from runtime, which matters more for open-sourcing than for the sudo threat specifically.
