# Changelog

All notable user-facing changes to FaradAI are documented here. For architectural reasoning behind decisions, see [DECISIONLOG.md](DECISIONLOG.md).

---

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

## [0.3.0-alpha.1] — 2026-05-27

### Breaking change

- `uninstall-faradai` now targets containers by label (`dev.faradai.managed=true`) instead of name pattern. Containers created before this change are not visible to uninstall; remove them manually with `docker rm -f faradai`.

### Added

- `jq` 1.7.1 included in the container image — available to agents and scripts running inside the container

### Security

- `faradai update` (tagged path) now prints a trust notice after tag verification passes: the update is verified by git tag over HTTPS but carries no GPG signature; you are trusting GitHub's infrastructure and the repository maintainer. GPG signing deferred until the formal release process is established ([DECISIONLOG](DECISIONLOG.md#2026-05-27--faradai-update-integrity-model-trust-warning-gpg-signing-deferred-44)) (#44)
- `faradai update --branch` gains two upfront warnings: branch tips are mutable; no integrity check is performed on branch updates (#44)

### Fixed

- `build.sh`: `dirname "$0"` replaced with `dirname "$(readlink -f "$0")"` so invoking via symlink uses the script's real directory as the Docker build context
- `_ensure_host_dirs`: now creates `~/.claude` before Docker runs, preventing Docker from creating it with root ownership on first use (#87)
- `faradai uninstall`: existence check before exec; prints a manual cleanup hint if binary is missing (#69)
- `faradai -v`: now prints version like `--version`/`version`; `faradai -a -v` also resolves to version (#61)
- `install.sh`: Docker presence and daemon-running preflight checks before invoking `build.sh` (#86)
- ARM64 support: ShellCheck binary download in the Dockerfile now uses `TARGETARCH` to select the correct archive (`amd64` → `x86_64`, `arm64` → `aarch64`); ARM64 builds previously silently downloaded the x86_64 binary (#74)
- `FARADAI_DEBUG=1` now prints an explicit warning to stderr before enabling `set -x`, stating that expanded shell variables may contain secrets or API keys and that AI agents reading this output will transmit it to their upstream inference servers (#45)
- `_append_credential_mount_args`: `~/.claude/.credentials.json` overlay now uses `_maybe_mount_file` instead of an unconditional `-v` mount. When the file is absent Docker was silently creating it as a directory, corrupting the host path and preventing Claude from ever writing credentials there

### Internal

- All `docker run` invocations now receive `--label dev.faradai.managed=true` and `--label dev.faradai.container-name=<name>` for reliable lifecycle scoping
- `_debug_print_plan`: comment documenting intentional `set -x` / `_exec_docker_run` ordering dependency (#89)
- `_UNINSTALL_BIN` injectable via env for testing; defaults to `/usr/local/bin/uninstall-faradai`
- Dockerfile: `base` stage extracts shared snapshot-repo configuration; `builder` and `final` both inherit `FROM base` ([DECISIONLOG](DECISIONLOG.md#2026-05-26-1713-utc--shared-base-stage-for-snapshot-configuration-83)) (#83)
- Dockerfile: `ARG SNAPSHOT_DATE=20260522T000000Z` pins Ubuntu apt sources to a single point-in-time snapshot for reproducible builds; all existing exact package version pins preserved ([DECISIONLOG](DECISIONLOG.md#2026-05-25-1713-utc--apt-reproducibility-strategy-ubuntu-snapshot-repos-83)) (#83)
- `test/libs/bats-core` added as git submodule at v1.9.0; tests now run via `test/libs/bats-core/bin/bats` (#62)
- 217 tests (was 142): new coverage for `_verify_update_tag`, `_resolve_latest_tag`, `_resolve_container_state` failure paths, `_debug_print_plan`, `_init_defaults` reset, SSH agent forwarding pipeline integration, and `_build_docker_run_args` OPTIONS-before-IMAGE ordering

## [0.4.0-alpha.1] — 2026-06-16

### Added

- `FARADAI_MOUNT_NIX_STORE`: opt-in (default `0`) bind-mount of the host's `/nix` store, `~/.config/nix`, and `~/.local/state/nix`, enabling flake-defined devShells (e.g. `nix develop`) inside the container. `/nix/store`, `~/.config/nix`, `~/.local/state/nix`, and `/nix/var/nix/profiles` are read-only; the rest of `/nix/var/nix` (Nix's mutable bookkeeping — `db`, `gcroots`, `temproots`, `gc.lock`, …) is writable on top, which Nix requires for any store-touching operation including read-only `nix develop`. Store *contents* stay immutable regardless. The image ships a `~/.nix-profile` symlink and `PATH` entry that resolve into the host's store when mounted, so the container always uses the host's Nix version — no separate version pin to maintain ([DECISIONLOG](DECISIONLOG.md#2026-06-15-1526-utc--faradai-shares-the-hosts-nix-store-blast-radius-controlled-by-filesystem-permissions-not-nix-config-99), [2026-06-16](DECISIONLOG.md)) (#99)
