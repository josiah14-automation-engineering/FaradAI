# FaradAI — Priority Index

Priority-ordered list of open GitHub issues. All content lives in the issues.

---

## Now

_(nothing — all shipped in v0.1.0-alpha.1)_

---

## Later

- [#45](https://github.com/josiah14-automation-engineering/FaradAI/issues/45) — `FARADAI_DEBUG=1` leaks environment variables to stderr without warning
- [#50](https://github.com/josiah14-automation-engineering/FaradAI/issues/50) — `_validate_cpus` float upper-bound check allows 128.5
- [#49](https://github.com/josiah14-automation-engineering/FaradAI/issues/49) — Docker mock in tests too permissive — can't test failure paths
- [#56](https://github.com/josiah14-automation-engineering/FaradAI/issues/56) — `entrypoint.sh` `_usage()` doesn't reflect current command surface
- [#51](https://github.com/josiah14-automation-engineering/FaradAI/issues/51) — No shell completion (bash/zsh/fish)
- [#26](https://github.com/josiah14-automation-engineering/FaradAI/issues/26) — Add `faradai prune` subcommand
- [#28](https://github.com/josiah14-automation-engineering/FaradAI/issues/28) — Read-only root filesystem opt-in (`FARADAI_READ_ONLY_ROOT`)
- [#9](https://github.com/josiah14-automation-engineering/FaradAI/issues/9) — Isolated Claude config for strict/client-work profile
- [#10](https://github.com/josiah14-automation-engineering/FaradAI/issues/10) — Isolated aider config for strict/client-work profile
- [#40](https://github.com/josiah14-automation-engineering/FaradAI/issues/40) — Migrate complex Bash scripting to Rash
- git mock for `_resolve_latest_tag` / `_verify_update_tag` unit tests (no issue yet)

---

## Deferred

- [#57](https://github.com/josiah14-automation-engineering/FaradAI/issues/57) — `build.sh --network=host` gives build container full host network access (accepted tradeoff, documented)
- [#58](https://github.com/josiah14-automation-engineering/FaradAI/issues/58) — Credential overlay `:ro` prevents writes but not reads (addressed in v2 via #29)

---

## v2

- [#29](https://github.com/josiah14-automation-engineering/FaradAI/issues/29) — Credential broker / proxy sidecar
- [#30](https://github.com/josiah14-automation-engineering/FaradAI/issues/30) — Per-project policy / config support
- [#31](https://github.com/josiah14-automation-engineering/FaradAI/issues/31) — Broker network mode (`FARADAI_NETWORK_MODE=broker`, depends on #29)
