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

