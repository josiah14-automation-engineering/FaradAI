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

Bug fixes, polish, and infrastructure items to complete before the Go/Nushell migration.

### Bug fixes & polish

- [#87](https://github.com/josiah14-automation-engineering/FaradAI/issues/87) — BUG: `_ensure_host_dirs` does not create `~/.claude` — Docker may create it with root ownership on first run
- [#86](https://github.com/josiah14-automation-engineering/FaradAI/issues/86) — `install.sh`: add Docker preflight check (docker present + daemon running)
- [#89](https://github.com/josiah14-automation-engineering/FaradAI/issues/89) — refactor: document `_debug_print_plan` / `set -x` ordering dependency
- [#69](https://github.com/josiah14-automation-engineering/FaradAI/issues/69) — BUG: `faradai uninstall` hardcodes `/usr/local/bin/uninstall-faradai` with no existence check
- [#61](https://github.com/josiah14-automation-engineering/FaradAI/issues/61) — `-v` short flag unhandled — falls through to docker; `-a -v` creates `faradai--v`
- [#42](https://github.com/josiah14-automation-engineering/FaradAI/issues/42) — `_build_extra_docker_args` rejects combined short-flag forms
- [#63](https://github.com/josiah14-automation-engineering/FaradAI/issues/63) — `build.sh` uses `dirname "$0"` which doesn't resolve symlinks
- [#82](https://github.com/josiah14-automation-engineering/FaradAI/issues/82) — enhancement: add managed container label (`dev.faradai.managed=true`) to scope uninstall
- [#56](https://github.com/josiah14-automation-engineering/FaradAI/issues/56) — `entrypoint.sh` `_usage()` doesn't reflect current command surface

### Needs discussion first

- [#83](https://github.com/josiah14-automation-engineering/FaradAI/issues/83) — enhancement: reconsider exact apt package pin strategy — pins without snapshot repos are brittle

### Infrastructure

- [#62](https://github.com/josiah14-automation-engineering/FaradAI/issues/62) — Pin bats-core to a specific tag in CI

---

## Later

Lower-priority items to complete before the Go/Nushell migration.

### Docs

- [#84](https://github.com/josiah14-automation-engineering/FaradAI/issues/84) — docs: security boundary wording, macOS Bash/SSH-agent caveats, logs/status with `--rm`, npm claim
- [#64](https://github.com/josiah14-automation-engineering/FaradAI/issues/64) — Docs: tmux in image list, URL casing, credentials `:ro` note
- [#47](https://github.com/josiah14-automation-engineering/FaradAI/issues/47) — SSH agent forwarding not covered in Troubleshooting section
- [#46](https://github.com/josiah14-automation-engineering/FaradAI/issues/46) — `uninstall-faradai`: document user data that persists after uninstall
- [#48](https://github.com/josiah14-automation-engineering/FaradAI/issues/48) — No CHANGELOG.md

### Other

- [#45](https://github.com/josiah14-automation-engineering/FaradAI/issues/45) — `FARADAI_DEBUG=1` leaks environment variables to stderr without warning
- [#49](https://github.com/josiah14-automation-engineering/FaradAI/issues/49) — Docker mock in tests too permissive — can't test failure paths
- [#55](https://github.com/josiah14-automation-engineering/FaradAI/issues/55) — `USER=$(whoami)` spawns unnecessary subshell — prefer `USER=${USER:-$(whoami)}`
- [#44](https://github.com/josiah14-automation-engineering/FaradAI/issues/44) — `faradai update`: no integrity verification on cloned `install.sh`
- git mock for `_resolve_latest_tag` / `_verify_update_tag` unit tests (no issue yet)

---

## After Go/Nushell Migration

Items deferred until after #65. The Bash-specific refactors may become irrelevant entirely.

### Migration acceptance criteria

- [#88](https://github.com/josiah14-automation-engineering/FaradAI/issues/88) — Track Bash alpha review findings as Go/Nu migration acceptance criteria (P1–P5 checklist)

### Portability

- [#74](https://github.com/josiah14-automation-engineering/FaradAI/issues/74) — BUG: Dockerfile ShellCheck download hardcoded to `linux.x86_64` — breaks ARM64 builds

### Refactoring (may become irrelevant)

- [#70](https://github.com/josiah14-automation-engineering/FaradAI/issues/70) — refactor: document globals written by `_parse_cli_flags`
- [#71](https://github.com/josiah14-automation-engineering/FaradAI/issues/71) — refactor: enforce or document SSH agent / credential mount temporal dependency
- [#72](https://github.com/josiah14-automation-engineering/FaradAI/issues/72) — refactor: document `DOCKER_RUN_ARGS` mutation chain across `_append_*` functions
- [#73](https://github.com/josiah14-automation-engineering/FaradAI/issues/73) — refactor: document intentional `set -x` scope in `_debug_print_plan`

### Security

- [#90](https://github.com/josiah14-automation-engineering/FaradAI/issues/90) — security: `install.sh` copies scripts to `/usr/local/bin` without post-clone integrity check
- [#91](https://github.com/josiah14-automation-engineering/FaradAI/issues/91) — security: `FARADAI_ALLOW_PUBLISH` / `FARADAI_ALLOW_DEVICE` enable host access with no secondary confirmation
- [#92](https://github.com/josiah14-automation-engineering/FaradAI/issues/92) — Spike: investigate LSM/seccomp hardening (SELinux, AppArmor, seccomp profiles)

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

---

## Won't Fix

- [#75](https://github.com/josiah14-automation-engineering/FaradAI/issues/75) — BUG: Bash 4+ syntax (`${var,,}`) breaks macOS default Bash 3.2 — portability addressed by Go/Nushell migration (#65)

---

## Planned

- [#29](https://github.com/josiah14-automation-engineering/FaradAI/issues/29) — Credential broker / proxy sidecar
- [#30](https://github.com/josiah14-automation-engineering/FaradAI/issues/30) — Per-project policy / config support
- [#31](https://github.com/josiah14-automation-engineering/FaradAI/issues/31) — Broker network mode (`FARADAI_NETWORK_MODE=broker`, depends on #29)
- [#65](https://github.com/josiah14-automation-engineering/FaradAI/issues/65) — Language strategy: migrate faradai to Go, support scripts to Nushell
- [#66](https://github.com/josiah14-automation-engineering/FaradAI/issues/66) — Post-v1.0.0: polyparadigm translation experiment
