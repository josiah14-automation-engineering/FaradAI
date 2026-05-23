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

