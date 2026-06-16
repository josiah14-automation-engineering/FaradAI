# FaradAI — Priority Index

Priority-ordered list of open GitHub issues. All content lives in the issues.

---

## Platform support

| Platform | Status |
|---|---|
| Linux | ✅ Primary — maintainer-tested |
| macOS (Docker Desktop) | ⚠️ Best effort — architecturally supported, not maintainer-tested (no Apple hardware) |
| Windows (WSL2 + Docker Desktop) | ⚠️ Best effort — likely works, not maintainer-tested |
| Windows (native) | ❌ Out of scope |
| FreeBSD / OpenBSD | ❌ No Docker support |

---

## Now

### Maintenance

- [#96](https://github.com/josiah14-automation-engineering/FaradAI/issues/96) — chore: bump Claude Code 2.1.143 → 2.1.167

### Features

- [#94](https://github.com/josiah14-automation-engineering/FaradAI/issues/94) — enhancement: optionally mount project source files `:ro` to prevent agent writes during code-author sessions — needed to safely use FaradAI while working on the Go/Nushell/Podman migration
- [#97](https://github.com/josiah14-automation-engineering/FaradAI/issues/97) — enhancement: add OpenCode and Codex CLI as supported agents

---

## After Go/Nushell Migration

Items deferred until after #65. The Bash-specific refactors may become irrelevant entirely.

### Security

- [#90](https://github.com/josiah14-automation-engineering/FaradAI/issues/90) — security: `install.sh` copies scripts to `/usr/local/bin` without post-clone integrity check
- [#91](https://github.com/josiah14-automation-engineering/FaradAI/issues/91) — security: `FARADAI_ALLOW_PUBLISH` / `FARADAI_ALLOW_DEVICE` enable host access with no secondary confirmation
- [#92](https://github.com/josiah14-automation-engineering/FaradAI/issues/92) — Spike: investigate LSM/seccomp hardening (SELinux, AppArmor, seccomp profiles)
- [#98](https://github.com/josiah14-automation-engineering/FaradAI/issues/98) — Spike: expose FaradAI as a remote dev container for IDE-centric agents (Cursor, Copilot)

### Features

- [#85](https://github.com/josiah14-automation-engineering/FaradAI/issues/85) — enhancement: per-user agent configuration — scope credential warnings to declared agents
- [#51](https://github.com/josiah14-automation-engineering/FaradAI/issues/51) — No shell completion (bash/zsh/fish)
- [#26](https://github.com/josiah14-automation-engineering/FaradAI/issues/26) — Add `faradai prune` subcommand
- [#28](https://github.com/josiah14-automation-engineering/FaradAI/issues/28) — Read-only root filesystem opt-in (`FARADAI_READ_ONLY_ROOT`)
- [#9](https://github.com/josiah14-automation-engineering/FaradAI/issues/9) — Isolated Claude config for strict/client-work profile
- [#10](https://github.com/josiah14-automation-engineering/FaradAI/issues/10) — Isolated aider config for strict/client-work profile

---

## Deferred

- [#57](https://github.com/josiah14-automation-engineering/FaradAI/issues/57) — `build.sh --network=host` gives build container full host network access (accepted tradeoff, documented)
- [#58](https://github.com/josiah14-automation-engineering/FaradAI/issues/58) — Credential overlay `:ro` prevents writes but not reads (tracked via #29)
- [#100](https://github.com/josiah14-automation-engineering/FaradAI/issues/100) — enhancement: broker-mediated Nix integration — stricter container policy, host-side gcroot management, IDE container `gcroots/auto` decision (v2 architecture; builds on #99's concluded spike)

---

## Won't Fix

- [#75](https://github.com/josiah14-automation-engineering/FaradAI/issues/75) — BUG: Bash 4+ syntax (`${var,,}`) breaks macOS default Bash 3.2 — portability addressed by Go/Nushell migration (#65)

---

## R&D

Educational explorations that don't directly advance the project but may surface ideas worth pulling in.

- [#40](https://github.com/josiah14-automation-engineering/FaradAI/issues/40) — Migrate complex Bash scripting to Rash — paradigm-first design exploration; may motivate targeted changes (e.g. miniKanren in select places) but not a direct project deliverable

---

## Planned

- [#29](https://github.com/josiah14-automation-engineering/FaradAI/issues/29) — Credential broker / proxy sidecar
- [#30](https://github.com/josiah14-automation-engineering/FaradAI/issues/30) — Per-project policy / config support
- [#31](https://github.com/josiah14-automation-engineering/FaradAI/issues/31) — Broker network mode (`FARADAI_NETWORK_MODE=broker`, depends on #29)
- [#65](https://github.com/josiah14-automation-engineering/FaradAI/issues/65) — Language strategy: migrate faradai to Go, support scripts to Nushell
- [#66](https://github.com/josiah14-automation-engineering/FaradAI/issues/66) — Post-v1.0.0: polyparadigm translation experiment
- [#93](https://github.com/josiah14-automation-engineering/FaradAI/issues/93) — Spike: mirror repo on Radicle for decentralized resilience
- [#99](https://github.com/josiah14-automation-engineering/FaradAI/issues/99) — Spike: decide whether FaradAI shares the host's Nix store or gets its own
