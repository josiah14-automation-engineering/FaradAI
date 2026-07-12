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

## [0.5.0-alpha.1] — 2026-07-09

### Added

- ARM64 (Apple Silicon / aarch64 Linux) is now a maintainer-tested platform — validated with a native build and smoke test on an M2 Mac running Asahi Linux. CI now builds and smoke-tests both `amd64` and `arm64` images on every push/PR.
- OpenCode CLI (`opencode`) support, closing out #97 (the other half, Codex, shipped separately). New host prerequisite: `opencode auth login`, with credentials mounted read-write from `~/.local/share/opencode/`. Same dispatch/preflight-credentials/HEALTHCHECK treatment as Claude Code/Codex/aider.

### Changed

- Claude Code bumped `2.1.177` → `2.1.205`.

### Fixed

- `gh`: the `cli.github.com` apt repo only ever serves the latest release, silently breaking the `gh=X.Y.Z` version pin whenever upstream ships a new version — on every architecture, not just ARM64. `gh` is now installed from a pinned GitHub Releases `.deb` instead, restoring reproducibility; bumped `2.95.0` → `2.96.0` in the process ([DECISIONLOG](DECISIONLOG.md#2026-07-08-1530-utc--gh-installed-from-a-pinned-github-releases-deb-not-the-cligithubcom-apt-repo)).

### Internal

- `_preflight_credentials` refactored from four copy-pasted per-tool blocks into a single data-driven loop over a tool→credential-path table — adding OpenCode as a 4th tool would otherwise have meant a 5th round of copy-paste.

## [0.5.0-alpha.2] — 2026-07-10

### Fixed

- aider's OpenRouter credentials were never actually reaching the container. `faradai aider` only ever mounted `~/.aider.conf.yml` — aider's real OAuth token (`~/.aider/oauth-keys.env`) and any per-model settings (`~/.aider.model.settings.yml`, e.g. OpenRouter Fusion panel/judge config) were invisible inside FaradAI, silently leaving aider unauthenticated or falling back to unintended (potentially paid) defaults. `~/.aider` is now mounted read-write (matching Claude/Codex/OpenCode), with `~/.aider/oauth-keys.env` pinned `:ro` on top — the same overlay treatment `~/.claude/.credentials.json` already gets; `~/.aider.model.settings.yml` is now mounted `:ro` alongside the existing `~/.aider.conf.yml` mount ([DECISIONLOG](DECISIONLOG.md#2026-07-10-1849-utc--aiders-openrouter-credentials-moved-out-of-aiderconfyml-into-a-ro-overlaid-aideroauth-keysenv)).
- `_preflight_credentials`'s aider check moved from `~/.aider.conf.yml` (which no longer implies working credentials now that the OAuth token lives elsewhere) to the actual credential file, `~/.aider/oauth-keys.env`.
- `faradai --version` / `faradai version` was printing a stale `0.3.0-alpha.1` — two releases behind — because `_FARADAI_VERSION` wasn't bumped alongside the last two releases. Corrected to `0.5.0-alpha.2`.

### Security

- `CLAUDE.md`'s "do not read" secrets warning was pointed at `~/.aider.conf.yml`, which is now stale: that file holds model-selection config only. Repointed at `~/.aider/oauth-keys.env`, the file that actually holds the OpenRouter token.

## [0.4.0-alpha.1] — 2026-06-16

### Added

- `FARADAI_MOUNT_NIX_STORE`: opt-in (default `0`) bind-mount of the host's `/nix` store, `~/.config/nix`, and `~/.local/state/nix`, enabling flake-defined devShells (e.g. `nix develop`) inside the container. `/nix/store`, `~/.config/nix`, `~/.local/state/nix`, and `/nix/var/nix/profiles` are read-only; the rest of `/nix/var/nix` (Nix's mutable bookkeeping — `db`, `gcroots`, `temproots`, `gc.lock`, …) is writable on top, which Nix requires for any store-touching operation including read-only `nix develop`. Store *contents* stay immutable regardless. The image ships a `~/.nix-profile` symlink and `PATH` entry that resolve into the host's store when mounted, so the container always uses the host's Nix version — no separate version pin to maintain ([DECISIONLOG](DECISIONLOG.md#2026-06-15-1526-utc--faradai-shares-the-hosts-nix-store-blast-radius-controlled-by-filesystem-permissions-not-nix-config-99), [2026-06-16](DECISIONLOG.md)) (#99)

## [0.6.0-alpha.1] — 2026-07-12

### Added

- `FARADAI_ENABLE_PONYTAIL` (opt-in, default `0`): provisions the [ponytail](https://github.com/DietrichGebert/ponytail) plugin ("laziest senior dev" minimal-code-generation hooks) for Claude Code, Codex, and OpenCode at launch. No aider integration — none exists upstream. Forced to `0` under `FARADAI_NETWORK_MODE=none` ([DECISIONLOG](DECISIONLOG.md#2026-07-11-1704-utc--ponytailheadroom-as-opt-in-flags-resolved-once-in-the-host-cli)).
- `FARADAI_ENABLE_HEADROOM` (opt-in, default `0`): launches any of the four agents wrapped via `headroom wrap`, a local context-compression proxy. Also forced to `0` under `FARADAI_NETWORK_MODE=none`.
- headroom pre-installed via pipx (`headroom-ai[proxy,code,html,reports,spreadsheet,otel]`) — deliberately narrower than `[all]` to avoid pulling in torch; see extras rationale ([DECISIONLOG](DECISIONLOG.md#2026-07-12-1404-utc--headroom-installed-with-narrow-pip-extras-memory-and-build-time-configurable-extras-deferred-65)).

### Fixed

- `docker exec` attach paths (`-a`, and auto-attach to an already-running container) now route through `entrypoint.sh` instead of execing the tool binary directly, so ponytail provisioning and headroom wrapping apply on every launch, not just a container's initial `docker run` ([DECISIONLOG](DECISIONLOG.md#2026-07-12-1237-utc--attach-mode-launches-route-through-entrypointsh-not-the-raw-tool-binary)).
- `~/.config` is now created and chowned to the container user during the image build, preventing Docker from auto-vivifying it as `root:root` (blocking tools like headroom from writing their own config subdirectory) when nested mounts (`~/.config/gh`, `~/.config/opencode`) attach without it already existing ([DECISIONLOG](DECISIONLOG.md#2026-07-12-1443-utc--config-pre-created-and-chowned-at-image-build-time)).

### Security

- Verified ponytail's runtime code makes no network calls of its own — it only injects instruction text into prompts already being sent to Anthropic's/OpenAI's API. Full verification in [DECISIONLOG](DECISIONLOG.md#2026-07-12-1409-utc--verified-ponytail-adds-no-new-external-network-exposure).

### Internal

- `~/.config/opencode/` now always mounted read-write (needed for `FARADAI_ENABLE_PONYTAIL=1` to merge its plugin entry into `opencode.json`), joining the existing `~/.local/share/opencode/` mount.
- Ponytail plugin installation stays launch-time rather than moving to a build-time-pinned install, after measurement showed the launch-time cost was already low in practice ([DECISIONLOG](DECISIONLOG.md#2026-07-12-1510-utc--ponytail-plugin-provisioning-stays-launch-time-not-build-time-pinned)).
- 288 tests (was 241): new coverage in `test/sourced.bats` and `test/unit.bats` for the feature-flag resolution/wiring pipeline, plus a new `test/entrypoint.bats` (24 tests) exercising `entrypoint.sh`'s provisioning and dispatch logic directly via call-logging mocks.
