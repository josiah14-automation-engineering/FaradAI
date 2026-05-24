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

- [#59](https://github.com/josiah14-automation-engineering/FaradAI/issues/59) — Pre-flight check: runtime `$USER` must match image's baked-in USERNAME
- [#67](https://github.com/josiah14-automation-engineering/FaradAI/issues/67) — BUG: stopped container creates dead-end — `_prepare_container_name_for_create` runs before `_remove_stale_container`
- [#70](https://github.com/josiah14-automation-engineering/FaradAI/issues/70) — refactor: document globals written by `_parse_cli_flags`
- [#71](https://github.com/josiah14-automation-engineering/FaradAI/issues/71) — refactor: enforce or document SSH agent / credential mount temporal dependency
- [#72](https://github.com/josiah14-automation-engineering/FaradAI/issues/72) — refactor: document `DOCKER_RUN_ARGS` mutation chain across `_append_*` functions
- [#73](https://github.com/josiah14-automation-engineering/FaradAI/issues/73) — refactor: document intentional `set -x` scope in `_debug_print_plan`

---

## Later

- [#60](https://github.com/josiah14-automation-engineering/FaradAI/issues/60) — `trap _cleanup` is dead code — remove or restructure
- [#61](https://github.com/josiah14-automation-engineering/FaradAI/issues/61) — `-v` short flag unhandled — falls through to docker; `-a -v` creates `faradai--v`
- [#62](https://github.com/josiah14-automation-engineering/FaradAI/issues/62) — Pin bats-core to a specific tag in CI
- [#63](https://github.com/josiah14-automation-engineering/FaradAI/issues/63) — `build.sh` symlink resolution
- [#64](https://github.com/josiah14-automation-engineering/FaradAI/issues/64) — Docs: tmux in image list, URL casing, credentials `:ro` note
- [#45](https://github.com/josiah14-automation-engineering/FaradAI/issues/45) — `FARADAI_DEBUG=1` leaks environment variables to stderr without warning
- [#50](https://github.com/josiah14-automation-engineering/FaradAI/issues/50) — `_validate_cpus` / `_validate_memory` float upper-bound check allows 128.5 / 512.5g
- [#49](https://github.com/josiah14-automation-engineering/FaradAI/issues/49) — Docker mock in tests too permissive — can't test failure paths
- [#56](https://github.com/josiah14-automation-engineering/FaradAI/issues/56) — `entrypoint.sh` `_usage()` doesn't reflect current command surface
- [#51](https://github.com/josiah14-automation-engineering/FaradAI/issues/51) — No shell completion (bash/zsh/fish)
- [#26](https://github.com/josiah14-automation-engineering/FaradAI/issues/26) — Add `faradai prune` subcommand
- [#28](https://github.com/josiah14-automation-engineering/FaradAI/issues/28) — Read-only root filesystem opt-in (`FARADAI_READ_ONLY_ROOT`)
- [#9](https://github.com/josiah14-automation-engineering/FaradAI/issues/9) — Isolated Claude config for strict/client-work profile
- [#10](https://github.com/josiah14-automation-engineering/FaradAI/issues/10) — Isolated aider config for strict/client-work profile
- [#40](https://github.com/josiah14-automation-engineering/FaradAI/issues/40) — Migrate complex Bash scripting to Rash
- [#68](https://github.com/josiah14-automation-engineering/FaradAI/issues/68) — BUG: no pre-flight check for `~/.claude` — missing credentials produce silent mount failure
- [#69](https://github.com/josiah14-automation-engineering/FaradAI/issues/69) — BUG: `faradai uninstall` hardcodes `/usr/local/bin/uninstall-faradai` with no existence check
- git mock for `_resolve_latest_tag` / `_verify_update_tag` unit tests (no issue yet)

---

## Deferred

- [#57](https://github.com/josiah14-automation-engineering/FaradAI/issues/57) — `build.sh --network=host` gives build container full host network access (accepted tradeoff, documented)
- [#58](https://github.com/josiah14-automation-engineering/FaradAI/issues/58) — Credential overlay `:ro` prevents writes but not reads (tracked via #29)

---

## Planned

- [#29](https://github.com/josiah14-automation-engineering/FaradAI/issues/29) — Credential broker / proxy sidecar
- [#30](https://github.com/josiah14-automation-engineering/FaradAI/issues/30) — Per-project policy / config support
- [#31](https://github.com/josiah14-automation-engineering/FaradAI/issues/31) — Broker network mode (`FARADAI_NETWORK_MODE=broker`, depends on #29)
