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

