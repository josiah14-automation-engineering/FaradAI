# Decision Log

Terse record of significant architectural and security decisions made after the first release (v0.1.0-alpha.1). For the full session-based development history through v1, see [BUILDLOG.md](BUILDLOG.md). For user-facing release notes, see [CHANGELOG.md](CHANGELOG.md).

Each entry: date, version scope, the decision, why, and alternatives considered.

---

## 2026-05-23 — `$USER` normalisation moved to `_init_defaults`

**Version scope:** post-alpha.1, part of the phase-pipeline refactor (session 42)

**Decision:** `USER="${USER:-$(whoami)}"` now runs in `_init_defaults`, the first phase called by `main()`, rather than deep inside the mount-building block.

**Why:** `_check_image_user` compared the image's baked-in username against `${USER}` before the `$(whoami)` fallback had run. In any context where `$USER` is not pre-set by the shell (cron, minimal service environments, some container entrypoints), the comparison would see `image_user != ""` and exit 1 with a false-positive "image was built for a different user" error. Moving the normalisation to `_init_defaults` ensures `USER` is valid before any downstream phase reads it.

**Alternatives considered:**
- Defensive `${USER:-$(whoami)}` at every use site — rejected; error-prone and doesn't fix the root ordering issue.
- Add `${USER:-$(whoami)}` only inside `_check_image_user` — would fix that function but leave other mount-path consumers (`_append_credential_mount_args`) at risk if they were ever called before the old normalisation line.

**Unconditional `_resolve_container_state`:** Also decided during this refactor — `_resolve_container_state` runs unconditionally even in create mode. Cost is one extra `docker inspect` process spawn; gain is one fewer branch in `main()`. Documented here because the plan flagged it as a decision to make.

---

## 2026-05-24 — Language strategy: Go for `faradai`, Nushell for support scripts

**Version scope:** forward-looking; migration not yet started

**Decision:** Migrate the `faradai` script to Go. Migrate post-install support scripts (`uninstall-faradai`, and any future equivalents) to Nushell. `install.sh` becomes a minimal bash bootstrapper that downloads and verifies a pinned nu binary, then hands off to a nu script for the actual installation work. `build.sh` and `entrypoint.sh` stay bash — both are short, stable, and `build.sh` runs on the host before nu is available.

**Why — Go for `faradai`:** The script has grown past 665 lines with 14+ extracted phase functions, a source guard, and a growing test suite. Bash's lack of a type system and the `set -e` / last-statement exit code footguns are active maintenance costs. Go gives a real type system, structured error handling, native unit testing, and produces a single portable binary. Contributor surface for Go is wide.

**Why — Nushell for support scripts:** The primary driver is macOS portability. macOS ships BSD versions of `sed`, `grep`, `awk`, `date`, and `stat` with different flags and behaviours from their GNU counterparts on Linux. Scripts that call these tools accumulate platform-divergence landmines as they grow. Nushell eliminates this class of problem entirely: its built-in commands (`str replace`, `where`, `get`, etc.) behave identically on Linux and macOS with no dependency on system tools. Nushell is also approachable for traditional ops contributors — it reads like a shell, supports piping and command execution naturally, and is less alien than something like Rash. Python was considered and rejected: it doesn't solve the runtime dependency problem, and it's clumsy for system scripting tasks that are mostly command execution, piping, and filesystem checks.

**Nushell in the container:** Nu will be installed in the faradai Docker image so that AI agents and contributors working on the project from inside a faradai box have the tool available. The same pinned nu version will be used in both the bundled binary and the container image.

**Alternatives considered:**
- Rash — more portable than bash but niche; would deter contributors unfamiliar with Lisp-adjacent syntax.
- Python — universally available but wrong ergonomics for shell-style scripting; doesn't solve the runtime dependency problem.
- Go for `install.sh` — would sidestep the nu bootstrapping problem but adds a second Go binary and unnecessary complexity for a short-lived installer script.
- Keep everything in bash — acceptable today; becomes a macOS portability liability as scripts grow.

---

## 2026-05-25 01:36 UTC — Ephemeral container stance; `_remove_stale_container` ordering and prompt (#67)

**Version scope:** pre-release correctness fixes

**Decision:** FaradAI takes an ephemeral stance on containers. Stopped containers are treated as stale state from abnormal termination (daemon restart, OOM kill, external `docker stop`) and are removed before a new container is created. `_remove_stale_container` is moved before `_prepare_container_name_for_create` in `main()`. Before removing a stopped container, `_remove_stale_container` prompts the user with a warning that container-local state (packages, files outside the bind-mounted project directory) will be lost. Running containers are left untouched by `_remove_stale_container`; `_prepare_container_name_for_create` handles the running-container conflict case.

**Why:** The previous ordering caused a dead-end: in `-c` (create) mode with a stopped container, `_prepare_container_name_for_create` found it via `docker inspect` and errored with an attach hint — but the container was not running and could not be attached to. With the swap, the stopped container is cleaned up first and the create proceeds. The prompt is added because stopped containers can hold meaningful state (even though `--rm` makes this an abnormal situation), and silent removal without warning would be a bad surprise.

**Alternatives considered:**
- Only block `-c` on running containers (check `_CONTAINER_RUNNING` instead of `docker inspect`) without reordering — would fix the hint but leave `_remove_stale_container` as a silent side effect.
- Warn and remove all FaradAI containers (not just the target) before create — rejected; would destroy unrelated named sessions as a side effect of starting a new one.

---

## 2026-05-25 01:36 UTC — Credential preflight with interactive recovery flow (#68)

**Version scope:** pre-release correctness fixes

**Decision:** Replace a simple abort-on-missing-credentials preflight with a `_preflight_credentials` phase that: (1) always warns if Claude credentials (`~/.claude/.credentials.json`) or aider configuration (`~/.aider.conf.yml`) are absent — even when not booting into the affected tool, to support agent-to-agent workflows; (2) triggers an interactive recovery flow only when the missing credential matches the boot target. Recovery offers numbered choices via a new `_prompt_choice` helper: boot into the alternative tool (if its credentials are present), or drop into bash to troubleshoot. If neither tool's credentials are present and the user is booting into either, only bash is offered. When the user selects an alternative tool, extra flags from `_CMD_ARGS` are dropped (they are tool-specific) and the recovery message names the flags being discarded. `_preflight_credentials` runs after `_maybe_attach_existing` so it is skipped entirely in attach mode.

**Why:** A bare die-on-missing-credentials approach is too blunt for a tool that supports multiple agents. Users who run both Claude and aider need to know the state of both credential sets at startup. The recovery flow avoids a dead-end where a user with a working aider setup is blocked from doing anything just because their Claude credentials have expired.

**Alternatives considered:**
- Simple preflight abort — too blunt; leaves the user with no path forward from the CLI.
- Carry extra flags through to the fallback tool — rejected; flags like `--resume` are tool-specific and passing them through would produce confusing errors in the target tool.
- Scope warnings to the boot target only — considered and rejected during implementation. Users who only use one agent would find unconditional warnings about the other agent noisy. However, the agent-to-agent argument (a Claude agent needs to know aider creds are missing before handing off) won out. The clean long-term fix is #85: let users declare which agents they use so warnings are scoped to declared agents. Deferred post Go/Nushell migration.


---

## 2026-05-25 — Managed container label targeting (#82)

**Version scope:** pre-release correctness fixes

**Decision:** Add `dev.faradai.managed=true` and `dev.faradai.container-name=<name>` labels to every `docker run` invocation. `uninstall-faradai` switches from `--filter "name=faradai"` name-pattern matching to `--filter "label=dev.faradai.managed=true"` for all container queries. No fallback to name-pattern matching.

**Why:** Name-pattern matching is brittle: it can't find custom-named containers (`-n NAME`) that don't start with `faradai`, and it could match unrelated containers with a `faradai` prefix. Label-based targeting is exact and opt-in. Breaking the old containers is an accepted alpha trade-off.

**Alternatives considered:**
- Keep name-pattern as fallback alongside label filter — rejected. The name-pattern is the problem we're retiring; keeping it as fallback preserves the bug for existing containers and complicates the code with deduplication logic.

---

## 2026-05-25 17:13 UTC — apt reproducibility strategy: Ubuntu snapshot repos (#83)

**Version scope:** pre-release correctness fixes

**Decision:** Adopt Ubuntu Snapshot Archive (`https://snapshot.ubuntu.com/ubuntu/<timestamp>`) for all Ubuntu apt sources in the Dockerfile. A single `ARG SNAPSHOT_DATE` in each build stage pins the snapshot, replacing the live `archive.ubuntu.com` and `security.ubuntu.com` mirrors. Exact package version pins (e.g. `git=1:2.43.0-1ubuntu7.3`) are preserved alongside the snapshot timestamp — together they guarantee both the package version and the repository state are reproducible. `Acquire::Check-Valid-Until "false"` is added to apt config so builds continue to work after the Release file's validity window expires. NodeSource and GitHub CLI repos remain as live third-party sources; their packages are still pinned by exact version.

**Why:** Exact version pins without a snapshot repo are the worst of both worlds: you pay the maintenance cost of pinning but don't get reproducibility, because upstream repos mutate and old package versions disappear. The snapshot repo closes that gap. A build against the same `SNAPSHOT_DATE` will produce the same package set regardless of when it runs.

**Alternatives considered:**
- Option A (relax pins, accept drift) — rejected. Reproducibility matters more than reduced maintenance burden at this stage of the project.
- Keep live mirrors with exact pins only — this is the status quo being replaced; it's brittle because a pinned version can vanish from upstream at any time.

**Maintenance note:** `SNAPSHOT_DATE` must be updated whenever package version pins are bumped. The snapshot timestamp should be set to a date on or after the date the new versions became available in the Ubuntu archive.

---

## 2026-05-26 17:13 UTC — Shared `base` stage for snapshot configuration (#83)

**Version scope:** pre-release correctness fixes

**Decision:** Extract a `base` stage (from the same `ubuntu:24.04` digest) that owns the snapshot source configuration — removing `ubuntu.sources`, writing `sources.list` with snapshot URLs for `noble`, `noble-updates`, and `noble-security`, and setting `Acquire::Check-Valid-Until "false"`. Both `builder` and `final` use `FROM base` instead of `FROM ubuntu:24.04` directly. `ARG SNAPSHOT_DATE` and `SHELL` are declared once in `base`.

**Why:** With `SNAPSHOT_DATE` declared independently in two stages, a maintainer bumping the snapshot can update one and miss the other — builder and final would silently resolve packages from different point-in-time snapshots, undermining the reproducibility guarantee. The `base` stage makes misalignment structurally impossible: one ARG, one RUN, one place to touch.

**Alternatives considered:**
- Duplicate the snapshot RUN in each stage — rejected. The duplication is a maintenance hazard that directly contradicts the reproducibility goal of the feature.
- Combine into one very large RUN across all stages — not possible in Docker multi-stage builds; each stage is an independent image layer graph.

---

## 2026-05-26 — BuildKit cache mounts rejected for npm/pipx installs (#83)

**Version scope:** pre-release correctness fixes

**Decision:** Do not use `--mount=type=cache` to accelerate npm and pipx installs in the builder stage. Rely solely on the existing GHA layer cache (`type=gha`) for build performance.

**Why:** BuildKit cache mounts operate at the download artifact level — they cache tarballs and wheel files outside the image layer graph, bypassing the snapshot URL entirely on cache hits. A warm cache would serve whatever was downloaded in a previous build, making it opaque to the snapshot framework and introducing a potential source of non-determinism. A stale or poisoned cache would produce a different image without any build failure or signal.

The GHA layer cache is the correct mechanism for a reproducibility-first build: it caches at the layer level. If Dockerfile inputs and build args are unchanged, the exact same layer is returned. If anything changes, the layer is rebuilt from scratch against the snapshot URL. That is the right granularity — fast when nothing changes, fully reproducible when something does.

The slow build cost from invalidating the GHA cache (caused by the base stage restructure in this same feature) is a one-time expense. Subsequent builds with unchanged layers will be fast via layer cache without compromising reproducibility.

**Alternatives considered:**
- BuildKit cache mounts — rejected; bypasses the snapshot URL on warm cache hits, undermining the reproducibility guarantee.
- Registry cache (GHCR) — not evaluated; would cache at the layer level like GHA and is worth revisiting if GHA cache eviction becomes a problem.

---

## 2026-05-27 — `faradai update` integrity model: trust warning, GPG signing deferred (#44)

**Version scope:** pre-release correctness fixes

**Decision:** Add trust-model disclosure to `faradai update` output. The existing `_verify_update_tag` check (which verifies that the cloned HEAD carries the expected tag via `git describe --exact-match --tags HEAD`) is retained as the primary integrity mechanism. A notice is now printed after the tag check passes, stating explicitly that: the tag was verified over HTTPS; no GPG signature is present; the user is trusting GitHub's infrastructure and the repository maintainer. For `--branch` updates (which skip tag verification entirely), two warnings are printed upfront: that branch tips are mutable and that no integrity check is performed.

GPG-signed tags are deferred until the formal release process is established. When adopted, every release tag will be signed with the maintainer's key (`git tag -s`), the public key will be published in the repository and on a separate channel, and `faradai update` will verify the signature with `git verify-tag` before proceeding. The `--branch` path will remain permanently unsigned.

**Why deferred:** GPG signing requires infrastructure that doesn't yet exist: a stable maintainer key, a published verification procedure, and a reliable key distribution channel. Implementing signing before the release process exists would produce a brittle check that breaks on first use. The tag-verification mechanism already prevents the most common update attacks (MITM drift between `ls-remote` query and clone); the remaining threat — a GitHub account or infrastructure compromise — is not meaningfully blocked by in-band SHA256 checksums (which an attacker with repo write access could also update).

**SHA256SUMS considered and rejected:** A `SHA256SUMS` file in the repository offers no additional protection against repository-level compromise — an attacker with write access to the repo also controls `SHA256SUMS`. It would only be meaningful if published on a separate channel (out-of-band), which requires the same publication infrastructure as a GPG key. Rejected until that infrastructure is in place.

**Alternatives considered:**
- In-repo SHA256SUMS — rejected; same trust level as the code itself if the repo is compromised.
- SHA256SUMS in GitHub Release assets — offers slightly stronger protection (assets are immutable once a release is published); worth revisiting once a formal release process exists.
- Immediate GPG signing — rejected for pre-alpha; the signing infrastructure doesn't exist and a broken signing check is worse than a disclosure-only approach.

---

## 2026-05-27 — FreeBSD support via Podman as part of Go/Nu migration (#65)

**Version scope:** post-v0.1.0-alpha, Go/Nu migration

**Decision:** FreeBSD support is targeted as part of the Go/Nushell CLI migration (#65). The blocker is the container runtime: Docker is not available on FreeBSD. The migration will switch from Docker to Podman, which has native FreeBSD support. Until the migration lands, FreeBSD is explicitly unsupported (not "no Docker" — "planned"). OpenBSD remains out of scope.

**Why Podman:** Podman is daemonless, rootless by default, and OCI-compatible — the same images and run flags work without modification. It is the natural drop-in replacement for Docker in environments where the Docker daemon is unavailable, including FreeBSD. The Go rewrite of `faradai` will abstract the container runtime behind a thin interface; switching the backend from `docker` to `podman` becomes a flag or compile-time choice rather than a script rewrite.

**Alternatives considered:**
- Jail-based isolation on FreeBSD without a container runtime — would require a completely separate implementation path and diverge from the OCI image model. Rejected.
- Keep "out of scope" for FreeBSD — rejected now that a clear path exists.

---

## 2026-05-27 04:47 UTC — Migration implementation strategy: Josiah writes all code; Emacs Systems IDE first (#65)

**Version scope:** Go/Nu/Podman migration

**Decision:** Josiah will implement the entire Go/Nushell/Podman migration (#65) by hand. AI assistance is scoped to guidance, concept explanation, design discussion, documentation interpretation, code review, issue tracking, and test running. AI will not produce Go, Nushell, or Podman integration code.

The first milestone before any migration code is written is setting up a Systems IDE in Emacs configured for Go and Nushell development (LSP, tooling, etc.).

**Why:** The migration is an intentional learning vehicle. Josiah wants to build working knowledge of Go, Nushell, and Podman through hands-on implementation rather than accepting generated code. Passive review of AI-produced code would not serve that goal.

---

## 2026-06-13 — Tool install layer split and ARG-based version pinning (#96)

**Version scope:** 0.3.0-alpha.2

**Decision:** Split the single `RUN` layer that installed both aider and Claude Code into two separate `RUN` layers — aider first, Claude Code second. Promote both version pins from inline literals to `ARG AIDER_VERSION` and `ARG CLAUDE_CODE_VERSION` declared in the `builder` stage.

**Why:** Claude Code releases significantly more frequently than aider. With a combined layer, any Claude Code version bump invalidates the entire layer and forces a full aider reinstall on every rebuild. The split ensures the aider layer stays cached across Claude Code updates. The ARG promotion moves both version pins to a single, obvious location at the top of the `builder` stage, eliminating the need to grep the install commands to find what's pinned.

**Alternatives considered:**
- Keep combined layer, accept reinstall cost — rejected; the aider install is slow and there is no reason to pay that cost for unrelated Claude Code bumps.
- ARGs only, no layer split — would improve discoverability but not build time; both changes together solve the full problem.

---

## 2026-06-13 16:48 UTC — OpenCode and Codex CLI prioritized for agent expansion; Cursor/Copilot deferred to remote-container spike (#97, #98)

**Version scope:** post-0.3.0-alpha.2, roadmap planning

**Decision:** OpenCode and Codex CLI are the next agents to add to FaradAI, bundled into a single ticket (#97). Cursor and GitHub Copilot — both IDE-centric agents — are deferred to a post-Go/Nu/Podman-migration spike (#98) investigating a Dev Containers-style remote development model.

**Why:** OpenCode and Codex CLI are both terminal/CLI-based like Claude Code and aider, so they fit FaradAI's existing "agent in a box" container model with no architectural change — same install/version-pin pattern, same credential-mount approach. OpenCode is currently the most-adopted open-source coding agent; Codex CLI extends that reach to the OpenAI ecosystem. Both are comparatively trivial additions, so they're tracked together rather than as separate tickets. Cursor and Copilot are IDE-integrated; supporting them well would require running an extension host as a service and exposing a port for the host IDE to connect to (the Dev Containers model). That is a significant departure from FaradAI's current ephemeral, no-exposed-ports, terminal-in/terminal-out security posture — every defense-in-depth control in the README assumes that shape — and deserves its own design doc once the Podman migration (#65) settles what port-exposure and service-isolation options are actually available.

**Alternatives considered:**
- Pursue Cursor/Copilot support now via the Dev Containers model — rejected; the security posture shift is large enough to warrant its own design conversation, and Podman's rootless mode (landing via #65) changes the available options, so designing this against the current Docker setup risks rework.
- Bundle OpenCode/Codex and the remote-container spike into the same milestone — rejected; both terminal agents are low-effort and unblocked today, while the spike is a multi-week investigation gated on #65. Splitting them lets the terminal-agent additions ship independently.
- Separate tickets for OpenCode and Codex CLI — rejected; both are the same category of low-effort terminal-agent addition following an identical pattern, so tracking them together avoids ticket sprawl for near-duplicate work.

---

## 2026-06-15 15:26 UTC — FaradAI shares the host's `/nix` store; blast radius controlled by filesystem permissions, not Nix config (#99)

**Version scope:** post-0.3.0-alpha.2, R&D — Nix integration spike (#99); implementation not yet started

**Decision:** FaradAI bind-mounts the host's `/nix` (store, profile, config) rather than installing an independent Nix. Within that mount: `/nix/store`, `~/.config/nix`, and `~/.local/state/nix` are **read-only** for agent sessions; `/nix/var/nix/db`, `/nix/var/nix/gcroots`, and `/nix/var/nix/temproots` are **read-write**. Agent-session `nix` additionally defaults to `--offline`/restricted `substituters` as defense-in-depth. FaradAI pins a `NIX_VERSION` matching the host and the docker-emacs IDE containers, which already share `/nix` via the same bind-mount pattern.

**Why — share, not an independent store:** The immediate driver is letting agent sessions use flake-defined devShells (e.g. project-pinned Mercury tooling) without a from-scratch Nix install in the FaradAI image. Sharing `/nix` gets store dedup with the host and IDE containers for free, at the cost of needing a coordinated `NIX_VERSION` across all consumers of the shared `/nix/var/nix/db`.

**Why — `/nix/store` read-only is the load-bearing control, not `--offline`:** Filesystem permissions are OS-enforced and can't be routed around by passing different flags to `nix`. Read-only `/nix/store` blocks *both* directions of "agent changes installed software": `nix build` / `nix flake update` / anything needing a path not already present fails on `EROFS` (can't add), and `nix-collect-garbage`/GC can't unlink existing paths (can't remove). Read-only `~/.config/nix` additionally prevents the agent from editing `nix.conf` to remove the `--offline` default. `--offline` itself remains as a second layer.

**Why `/nix/var/nix/db` is read-write, not read-only:** Nix's `db.sqlite` runs in WAL mode, and per SQLite's own docs a WAL-mode database "cannot generally be opened from read-only media because even ordinary reads... require recovery-like operations." Nix's `read-only`/`immutable=1` local-store setting doesn't close this for us: [NixOS/nix#2196](https://github.com/NixOS/nix/issues/2196) found the implementation incomplete (some `sqlite3_open_v2()` call sites still pass `SQLITE_OPEN_READWRITE` regardless of the flag) and was closed stale, unfixed; separately, `immutable=1` assumes no concurrent writers, which is false here (host + IDE containers actively write the same `db.sqlite`). This doesn't weaken the design — a writable-but-possibly-stale `db.sqlite` can't make files appear in or vanish from a read-only `/nix/store`, so it's inert from a "can the agent change installed software" standpoint. Full research trail in the #99 comments.

**Alternatives considered:**
- Independent Nix install for FaradAI (no store sharing) — rejected; loses dedup and reopens "does FaradAI need Nix at all" without answering it.
- `--offline`/config-level restriction as the *primary* mechanism, no read-only mounts — rejected; it's agent-editable state (`nix.conf`), not an OS-enforced boundary. Demoted to defense-in-depth.
- `/nix/var/nix/db` read-only via `immutable=1` — investigated and rejected per the WAL findings above. Closed line of inquiry, not a TODO.

---

## 2026-06-15 16:20 UTC — Nix mount toggle implemented host-mount-only; no baked-in Nix, no `NIX_VERSION` pin (#99)

**Version scope:** post-0.3.0-alpha.2 — implements the 2026-06-15 15:26 UTC decision (#99)

**Decision:** `FARADAI_MOUNT_NIX_STORE` (default `0`) gates a new `_append_nix_mount_args` function implementing the read-only/read-write split from the prior entry. The Dockerfile adds only a `~/.nix-profile -> ~/.local/state/nix/profiles/profile` symlink and a `PATH` entry — both dangling/harmless when the toggle is off. This refines the prior entry's assumption of a baked-in `nix-source` stage and a `NIX_VERSION` pin (mirroring docker-emacs systems-ide): **neither exists**. The container has no Nix of its own; `nix` is available only when the toggle is on, resolving entirely through the host's mounted `/nix/store` and profile chain.

**Why — drop the baked-in stage and `NIX_VERSION` pin:** The shared `/nix/var/nix/db` (read-write per the prior entry's WAL finding) is written by whatever Nix version touches it. A baked-in FaradAI-image Nix that drifts from the host's version would mean *two* Nix versions writing the same `db.sqlite` — reintroducing the cross-version-db hazard the shared-store decision exists to dedup away, one layer down, plus an ongoing manual version-sync chore. Host-mount-only means there is only ever one Nix version touching the shared db (the host's), and the container tracks host Nix upgrades automatically with zero FaradAI-side changes.

**Why — `NIX_CONFIG`/`--offline` defense-in-depth was evaluated and not added:** `NIX_CONFIG` is a plain environment variable; the agent's own shell can `export`/`unset` it for itself and anything it spawns, so it provides no enforcement — only a default that a deliberate agent bypasses trivially. The load-bearing controls are unchanged from the prior entry and already exist: `/nix/store:ro` (kernel `EROFS`, unaffected by any `nix.conf`/`NIX_CONFIG`/CLI combination) plus the existing `--cap-drop ALL` in `_append_security_args`, which already drops `CAP_SYS_ADMIN` and therefore blocks `mount -o remount,rw` from inside the container regardless of who's asking.

**Why — per-tool (Nix-only) network restriction was not pursued:** Investigated whether `nix` specifically could be denied network access while other tools (git, npm, curl) retain it. Not expressible at the kernel level — network namespaces, netfilter `-m owner --uid-owner`, and seccomp all operate on process/UID/namespace, not "which binary," and every tool in a FaradAI session shares one UID and one network namespace. Giving `nix` its own UID or netns is a real architectural change, not in scope here. For the current use case this is moot: `nix develop` against an already-realized closure needs no network at all, so `FARADAI_NETWORK_MODE=none` is already compatible with the expected workflow. The general point — that per-tool network policy requires an application-layer mediator, not a kernel-layer one — is recorded on [#29](https://github.com/josiah14-automation-engineering/FaradAI/issues/29) for the credential-broker migration, which is exactly that kind of mediator.

**Alternatives considered:**
- Baked-in `nix-source` stage (`FROM josiah14/nix:2.34.7-ubuntu-24.04 AS nix-source`) + `COPY --from=nix-source` of `/nix`, `~/.config/nix`, `~/.local/state/nix`, plus a `NIX_VERSION` ARG, mirroring docker-emacs systems-ide — drafted, then reverted. Rejected per the cross-version-db reasoning above.
- `NIX_CONFIG="substituters =\ntarball-ttl = ..."` as a container-launch env var approximating `--offline` — investigated, not implemented; not an enforcement boundary, and the prior entry already correctly demotes `--offline` to defense-in-depth, which on inspection has no teeth here regardless of mechanism.
- Per-tool network isolation for `nix` via netns/seccomp/UID separation — investigated, not pursued; disproportionate to the actual need and not kernel-expressible at single-tool granularity. Tracked on #29 instead.

**Forward reference:** #29 (credential broker) gets a note on how agent-session `nix` fetch traffic fits the broker model if read-only `/nix` ever needs a controlled exception.

---

## 2026-06-16 — `nix develop` lock fix: all of `/nix/var/nix` read-write (profiles re-pinned read-only); `LD_PRELOAD` shim tried and removed (#99)

**Version scope:** post-0.3.0-alpha.2 — fixes the read-only/read-write split from the 2026-06-15 entries (#99)

**Decision:** `_append_nix_mount_args` now mounts **all of `/nix/var/nix` read-write** (replacing the `db`/`gcroots`/`temproots`-only sub-mounts), with **`/nix/var/nix/profiles` re-pinned read-only** via a nested bind-mount. `/nix/store`, `~/.config/nix`, and `~/.local/state/nix` stay read-only as before. The `LD_PRELOAD` C shim drafted to work around this (`nix-temproots-fix.{c,map}`, a `shim` build stage, a container-wide `ENV LD_PRELOAD`) is **removed** — it never addressed the real cause.

**Root cause (misdiagnosed first):** `FARADAI_MOUNT_NIX_STORE=1 nix develop` failed with `error: acquiring/releasing lock: Bad file descriptor`. The prior split made `db`/`gcroots`/`temproots` writable but **missed `/nix/var/nix/gc.lock`**, which lives directly under `/nix/var/nix` and so fell on the read-only `/nix` mount. Nix opens `gc.lock` `O_RDWR|O_CREAT` for any store-touching operation (it locks GC out while registering temproots); on the read-only mount that `open` returns `EROFS`, leaving fd `-1`, and the subsequent lock on `-1` surfaces as `EBADF`. A low-overhead `LD_PRELOAD` trace (logging `open*` returns + errno) caught it: `open64(".../temproots/<pid>") = 11` (success) immediately followed by `open64(".../gc.lock") = -1 EROFS`. `strace` had hidden the failure — under it, evaluation hit cache and never re-copied the dirty flake tree, so `addTempRoot`/`gc.lock` was never reached (a caching Heisenbug, not a ptrace timing effect).

**Why all of `/nix/var/nix`, not just `gc.lock`:** `/nix/var/nix` is Nix's mutable *bookkeeping* (db, gcroots, temproots, gc.lock, profiles, builds), distinct from package *contents* in `/nix/store`. Carving out individual sub-paths is what produced this bug (forgot one), and a single-file bind-mount of `gc.lock` is fragile — it binds to the current inode and breaks if Nix ever recreates the file. Mounting the whole state dir matches the real boundary ("Nix's mutable state is writable; the store is not") and is robust against future state files.

**Why this does not weaken the load-bearing guarantee:** `/nix/store` stays read-only (kernel `EROFS`) and `--cap-drop ALL` blocks `mount -o remount,rw`, so store *contents* remain immutable — the agent still cannot add, alter, or delete installed software. Writable `/nix/var/nix` only exposes mutable bookkeeping; the worst a compromised container can do is corrupt shared Nix state → DoS/cleanup for host + sibling containers (recoverable via `nix-store --verify --repair` / `db.bak`), never code injection. Most of that risk (writable `db`) already existed.

**Why `profiles` is re-pinned read-only:** it is the one part of `/nix/var/nix` a compromised container could use to tamper with the **host's** profile generations (redirecting them among already-built store paths). `nix develop` never writes `profiles` — dev-shell GC roots go under `gcroots/auto/` — so pinning it read-only costs nothing and removes that vector. Same bet #99 already makes with `~/.local/state/nix:ro`.

**The shim detour (recorded so it isn't re-attempted):** before `gc.lock` was found, the failure was misattributed to a supposed Nix 2.34.x bug — opening `temproots` `O_RDONLY` then write-locking → `EBADF`. An `LD_PRELOAD` shim was built to flip `O_RDONLY→O_RDWR`, including glibc symbol-versioning (`.symver` + version script) so it would intercept `open64@GLIBC_2.2.5`. It never worked because the premise was false: `ctypes` probes proved this kernel accepts a write lock (`F_SETLK`, `F_OFD_SETLK`, `F_OFD_SETLKW`) on an `O_RDONLY` fd, and the real `temproots` open is already `O_RDWR`. No `open()` flag change can fix an `EROFS` open regardless. Removed entirely — dead code plus a container-wide `LD_PRELOAD` blast radius for zero benefit.

**Alternatives considered:**
- Forward the host `nix-daemon` socket into the container so container-`nix` writes via the host daemon — **rejected**; the daemon has write access to the real store, so this routes around the read-only `/nix/store` boundary entirely (Josiah caught this and pulled the plug). #99's whole premise is that the boundary is kernel-enforced, not delegated.
- `LD_PRELOAD` `open`-flag shim — built, disproven, removed (above).
- `gc.lock`-only writable file bind-mount (narrowest surface) — viable but fragile (inode rebind) and reopens whack-a-mole; rejected for the whole-dir mount with a `profiles` carve-out.
