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

---

## First Successful Run — 2026-05-11

Josiah confirmed Claude Code running inside the container. The filesystem boundary, user identity mirroring, `~/.claude` credential passthrough, and `~/Development/personal` mount all functioned as designed on the first attempt.

---

## Session 2 — 2026-05-13

### Aider Integration

Josiah added `aider` to the container and configured it with an OpenRouter API key (`OPENROUTER_API_KEY` env var), giving the container a second AI coding tool alongside Claude Code. Aider was confirmed functional via a smoke test against `openrouter/anthropic/claude-3-haiku`, which returned a response and cost breakdown on the first attempt.

### Memory Passthrough Confirmed

**Josiah verified** that the `~/.claude` mount carries not just credentials but also the full persistent memory system (`~/.claude/projects/.../memory/`). Memory files written in prior sessions are accessible inside the container, meaning context and collaboration preferences persist across container restarts without any additional mounting or configuration.

### Ring-2.6-1T Code Review

Ring-2.6-1T (via aider/OpenRouter) reviewed the FaradAI project files and produced a prioritized issue table. The high-severity finding was a security inconsistency: `run.sh` passes `OPENROUTER_API_KEY` as an environment variable despite the BUILDLOG explicitly documenting that env vars are visible to the agent. Additional findings covered `.dockerignore` absence, version pinning, resource limits, and minor shell style.

**Josiah reviewed the findings and accepted the env var exposure as a known tradeoff.** The `OPENROUTER_API_KEY` carries a hard cost limit, making the blast radius of any leak bounded and tolerable. The risk is acknowledged, not overlooked.

---

### Lesson: Environment Variables Are Not Secret from the Agent

During the aider smoke test, a broad `env | grep` command was used to check for relevant API keys. The full `OPENROUTER_API_KEY` value appeared in the tool output and was transmitted to Anthropic's servers as part of the conversation context. The key had a cost limit, so exposure was low-risk, but the pattern is worth noting.

**The Faraday cage protects the filesystem boundary, not the process environment.** Any secret present as an environment variable is visible to the agent and will be transmitted if it appears in tool output. Mitigations:

- Scope `env` greps to exactly the variable name you intend to expose.
- Keep secrets out of the container environment entirely when possible (e.g., inject only at the point of use, or store outside the mount).
- Prefer keys with tight cost limits and short rotation cycles for anything used inside AI coding sessions.
