# Changelog

All notable user-facing changes to FaradAI are documented here. For architectural reasoning behind decisions, see [DECISIONLOG.md](DECISIONLOG.md).

---

## [Unreleased]

## [0.1.0-alpha.1] — 2026-05-22

Initial release. Core features:

- `faradai` CLI — runs Claude Code and aider in a sandboxed Docker container with an OS-level filesystem boundary
- Subcommands: `claude`, `aider`, `bash`, `logs`, `status`, `version`, `update`, `uninstall`
- Resource limits: `FARADAI_MEMORY`, `FARADAI_CPUS`, `FARADAI_PIDS`
- Network control: `FARADAI_NETWORK_MODE=open|none`
- SSH agent forwarding with confirmation prompt
- `faradai update` pulls the latest tagged release with integrity verification; `--branch NAME` for pre-release testing
- `shellcheck` v0.11.0 included in the image
- 43 unit tests (bats)

## [0.2.0-alpha.1] — 2026-05-23

### Breaking change

- CLI flag grammar replaced. Old: `faradai -a myproject` (name as positional arg to `-a`). New: `faradai -a -n myproject` (flags are orthogonal).
  - `-c` — create mode; error if container already exists
  - `-a` — attach mode; error if not running
  - `-n NAME` — name selector; works with `-c`, `-a`, or auto-detect
  - Auto mode (no flags) is unchanged

### Fixed

- `$USER` normalisation moved to `_init_defaults`, fixing a false-positive "image was built for a different user" error in environments where `$USER` is unset at launch time (cron, minimal service entrypoints)

### Internal

- Phase pipeline refactor: `main()` is now a linear sequence of named functions with explicit Reads/Writes contracts
- Single `DOCKER_RUN_ARGS` accumulator replaces per-category arrays
- Source-vs-execute guard enables function-level unit testing without docker mock limitations
- 142 tests (was 43): added `test/sourced.bats` for function-level phase coverage

## [Unreleased]

### Breaking change

- `uninstall-faradai` now targets containers by label (`dev.faradai.managed=true`) instead of name pattern. Containers created before this change are not visible to uninstall; remove them manually with `docker rm -f faradai`.

### Internal

- All `docker run` invocations now receive `--label dev.faradai.managed=true` and `--label dev.faradai.container-name=<name>` for reliable lifecycle scoping

### Fixed

- `build.sh`: `dirname "$0"` replaced with `dirname "$(readlink -f "$0")"` so invoking via symlink uses the script's real directory as the Docker build context
