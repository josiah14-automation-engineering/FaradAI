# FaradAI — Open Items

---

## Pre-open-source: multi-stage build

**Priority: do this before publishing.**

Move to a multi-stage Dockerfile. Do all root-level setup in a builder stage, then `COPY --from=builder` only the needed artifacts into a clean minimal base.

**Why:** `apt-get purge sudo` writes a whiteout entry — it hides sudo at runtime but doesn't remove it from earlier layers. Anyone who extracts the image tarball and mounts a pre-purge layer gets the binary directly. The `ubuntu:24.04` base layer itself ships with sudo and is immutable; no amount of purging in subsequent layers removes it from that layer's archive. A multi-stage build is the only way to produce a final image whose layer history never includes a sudo binary.

---

## `--pids-limit` in `run.sh`

Ring flagged resource limits; `--memory` and `--cpus` were added, but `--pids-limit` was not. An AI agent running shell commands that fork heavily (parallel tool calls, recursive find, etc.) could exhaust the process table. A conservative value like `--pids-limit 512` would bound that.

---

## Python: confirm it's needed or trim it

Python 3 + pip + venv adds ~150MB to the image (Ring finding). Currently justified in `CLAUDE.md` as "available for intermediate scripting tasks." Before open-sourcing, decide: is Python genuinely used enough to keep, or should it be dropped to reduce image size? If kept, add a one-line justification to the README.

---

## CLAUDE.md: add system-path guardrail

Ring observation: "Never search above this directory" is good, but the agent isn't explicitly told to stay away from system paths like `/etc`, `/root`, or other paths outside the mount that are still reachable inside the container. Add an explicit instruction prohibiting inspection or modification of system-level paths as a defense-in-depth layer alongside the filesystem mount boundary.

---

## README: stale open items table

The "Open items" table at the bottom of `README.md` lists five issues — all five have since been resolved (`.dockerignore`, version pinning, SSH mount, `ENTRYPOINT`, sudo removal). The table should be removed or replaced with the current state.
