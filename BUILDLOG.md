# FaradAI Build Log

---

## Session 1 — 2026-05-11

### Motivation

Josiah observed that a prior Claude Code session had invoked `find ~`, scanning broadly across his home directory. He identified this as an unacceptable intrusion and decided the correct architectural response was to run Claude Code inside a Docker container with only the relevant project directory mounted — creating a hard filesystem boundary rather than relying on behavioral constraints alone.

### Naming

Rather than a generic name like `containerized-ai`, Josiah proposed **FaradAI** — a portmanteau of *Faraday cage* (electromagnetic isolation) and *AI*. The analogy is precise: a Faraday cage doesn't weaken the signal inside, it constrains what can escape or be reached from outside. Directory name: `faradai`.

### Base Image & Dockerfile

- Base image: `ubuntu:24.04`, consistent with the `docker-emacs` 30.2 images in this repo.
- **Josiah caught** that Ubuntu 24.04 ships with a default `ubuntu` user at UID/GID 1000, which would clash when creating a host-mirrored user. He directed adding explicit `userdel`/`groupdel` cleanup before the new user is created.
- **Josiah directed** including Python 3 and pip, anticipating that Claude Code may invoke Python for intermediate tasks (data manipulation, scripting, etc.).

### Mount Layout

Initial plan used a generic `/workspace` mount. **Josiah redirected** this to mirror the host machine's actual layout: `~/Development/personal` mounted to the same path inside the container. This means project-relative paths, memory references, and tooling all behave identically inside and outside the container.

### Build Script

**Josiah specified** that `build.sh` must not hardcode any personal information (username, UID, GID). The script derives all three at runtime via `$(whoami)`, `$(id -u)`, and `$(id -g)`, making it portable to any host user without modification.

### Authentication

Josiah questioned how to auto-provide the Anthropic API key, noting he had logged in via `claude login` rather than setting an environment variable. Investigation confirmed that `claude login` stores OAuth credentials in `~/.claude/.credentials.json`. Since `run.sh` already mounts `~/.claude` into the container, authentication is inherited automatically — no API key env var is needed. The `-e ANTHROPIC_API_KEY` line was removed from `run.sh`.
