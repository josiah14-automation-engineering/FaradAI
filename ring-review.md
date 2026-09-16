# Faradai Shell Script — Code Review

> Historical review of `faradai` 0.2.0-alpha.1. Findings may have been fixed or
> superseded; use current code, tests, and `DECISIONLOG.md` for present behavior.

**File:** `faradai`
**Date:** 2026-05-24
**Reviewer:** Ring-2.6-1T (via aider)
**Version reviewed:** 0.2.0-alpha.1

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architectural Quality](#2-architectural-quality)
3. [Best Practices & Shell Style](#3-best-practices--shell-style)
4. [Correctness — Bugs & Edge Cases](#4-correctness--bugs--edge-cases)

---

## 1. Executive Summary

The faradai script is remarkably well-structured for a Bash CLI tool. The phase-based orchestration in `main()` is clear, error messages are consistent and go to stderr, and defensive patterns like `|| true` and `${var:+...}` are used appropriately. However, the review surfaced **one critical correctness bug** (stale container ordering), **one significant correctness bug** (whitespace in `-n` names), and several moderate issues worth addressing.

---

## 2. Architectural Quality

### 2.1 Phase Structure — ✅ Strong

The `main()` function orchestrates a clean linear pipeline:

```
init → parse flags → dispatch meta → preflight Docker → dispatch metadata →
ensure image → resolve workdir → resolve state → maybe attach →
confirm trust → handle SSH → prepare create → remove stale →
setup trap → load config → ensure dirs → build args → debug → exec
```

Each phase is a discrete function with a single responsibility. Excellent for a shell script of this complexity.

### 2.2 Separation of Concerns — ✅ Good

- **Meta commands** (`_dispatch_meta_commands`) are cleanly separated from Docker-dependent commands.
- **Docker metadata commands** (`_dispatch_docker_metadata_commands`) are separated from the create/attach lifecycle.
- **Build steps** (`_append_*_args` functions) each handle one concern for constructing the `docker run` invocation.

### 2.3 Coupling Concerns — ⚠️ Moderate

**Finding A: `_parse_cli_flags` mutates five global variables**

`_parse_cli_flags` writes to `_MODE`, `_CONTAINER_NAME`, `_CMD_ARGS`, and reads `_MODE`. These are undeclared globals with no explicit interface contract. Any refactor must track all five side effects.

**Recommendation:** Add a comment block documenting the globals written by `_parse_cli_flags`, or group them into a single associative array.

**Finding B: `_handle_ssh_agent_forwarding` must precede `_append_credential_mount_args`**

`_SSH_AGENT_APPROVED` (set by `_handle_ssh_agent_forwarding`) is read by `_append_credential_mount_args`. The ordering is correct in `main()`, but there is no programmatic enforcement. A future refactor that reorders calls would silently break SSH agent forwarding.

**Recommendation:** Add a comment coupling these two functions, or merge them into a single `_build_credential_config` phase.

### 2.4 Shared-State Globals — ⚠️ Moderate

`DOCKER_RUN_ARGS` is a global array mutated by seven `_append_*` functions. This is a form of "out parameter" pattern. While functional, it makes the data flow harder to trace. Any accidental reordering could produce incorrect Docker invocations.

**Recommendation:** Consider adding a diagram of the mutation chain, or returning a value from a single orchestrator that composes all flags.

---

## 3. Best Practices & Shell Style

### 3.1 `set -euo pipefail` — ✅ Correct

All three strict modes are enabled. The script correctly handles the pitfalls:

- **`set -e` + `(( ))` in conditions**: Arithmetic in `if`/`||` contexts is safe — `(( 0 ))` returns 1 but doesn't trigger errexit when part of a compound command.
- **`set -e` + `|| true`**: Pipelines that may fail (e.g., `head -1`) are correctly guarded.
- **`set -u` + `${var:-default}`**: All optional environment variables use the `:-` expansion, preventing unbound-variable errors.

### 3.2 ShellCheck Compliance — ✅ Mostly Clean

| Pattern | Status |
|---|---|
| `SC2064` (trap expansion) | Handled — `# shellcheck disable=SC2064` present, intentional |
| `SC2086` (unquoted variables) | Clean — all variable expansions are properly quoted |
| `SC2162` (read without -r) | Clean — `read -r` used throughout |
| `SC2207` (word splitting arrays) | Clean — `read -ra` used for splitting |

### 3.3 Naming Conventions — ✅ Consistent

- **`UPPER_SNAKE_CASE`** for environment variables (`FARADAI_*`) — correct.
- **`_lower_snake_case`** with `_` prefix for internal functions — correct and idiomatic.

### 3.4 Error Handling — ✅ Good

- `_die` provides consistent error formatting and always exits with code 1.
- All error messages go to stderr (`>&2`).
- The `_usage` function is comprehensive and kept up-to-date with the actual command set.

### 3.5 Defensive Patterns — ✅ Good

- `${_args[_i]//[[:space:]]/}` strips all whitespace classes to detect whitespace-only names — thorough.
- `${_CMD_ARGS[@]+"${_CMD_ARGS[@]}"}` safely handles potentially empty arrays.
- `_resolve_container_state` uses `|| _CONTAINER_RUNNING=""` to handle `docker inspect` failure without triggering errexit.

---

## 4. Correctness — Bugs & Edge Cases

### 🔴 BUG-1: Stale container blocks `create` mode (Critical)

**Affected functions:** `_prepare_container_name_for_create`, `_remove_stale_container`

The call order in `main()` is:

```
_prepare_container_name_for_create   # exits if container exists (any state)
_remove_stale_container               # removes stopped containers
```

If a stopped/stale container named `faradai` exists, `_prepare_container_name_for_create` calls `docker inspect`, finds it, and exits with:

```
faradai: container 'faradai' already exists — attach with: faradai -a
```

But `faradai -a` also fails because the container isn't running:

```
faradai: no running container 'faradai' — start one with: faradai
```

The user is stuck in a dead end. `_remove_stale_container` (which would fix this) is never reached.

**Why it matters:** This happens after an interrupted session, a Docker crash, or any unclean shutdown. The cleanup trap mitigates this, but `set -e` + `exec docker run` means the trap only fires on signals, not on Docker daemon failures.

**Fix:** Swap the order — call `_remove_stale_container` before `_prepare_container_name_for_create`. Then change `_prepare_container_name_for_create` to only check for *running* containers (knowing stale ones have already been removed).

---

### 🔴 BUG-2: `-n` flag accepts names with internal whitespace (Significant)

**Affected function:** `_parse_cli_flags`

The whitespace check (`[[:space:]]` stripping) only rejects names that are **entirely** whitespace. A name like `"my project"` passes validation because it contains non-whitespace characters. However, Docker container names cannot contain spaces. This produces:

```
_CONTAINER_NAME="faradai-my project"
```

Every subsequent `docker` command using `_CONTAINER_NAME` will break or behave unexpectedly.

**Why it matters:** A user who passes `-n "my project"` gets a cryptic Docker error rather than a clear validation message.

**Fix:** Add `[[ "${_args[_i]}" =~ [[:space:]] ]] && _die "-n name cannot contain whitespace"`.

---

### 🟡 BUG-3: `_ensure_host_dirs` doesn't ensure `.claude` directory (Moderate)

**Affected functions:** `_ensure_host_dirs`, `_append_credential_mount_args`

`_ensure_host_dirs` only creates `${HOME}/.config/gh`. But `_append_credential_mount_args` mounts `${HOME}/.claude` as a directory. If `${HOME}/.claude` does not exist on the host, Docker creates it as an empty directory, which could cause authentication failures that are hard to diagnose on first run.

**Fix:** Add `${HOME}/.claude` to `_ensure_host_dirs`, or validate that the expected credential files exist and warn if they're missing.

---

### 🟡 BUG-4: `uninstall` assumes binary path without validation (Moderate)

**Affected function:** `_dispatch_meta_commands`

`exec /usr/local/bin/uninstall-faradai` is hardcoded. If the binary doesn't exist (non-standard install, failed prior installation, different prefix), the script exits with a generic Bash "not found" error rather than a helpful message.

**Fix:** Check for the binary first and provide a clear error with alternative instructions.

---

### 🟡 BUG-5: `_resolve_latest_tag` relies on `--sort=-version:refname` (Minor)

**Affected function:** `_resolve_latest_tag`

`--sort=-version:refname` requires Git ≥ 2.0. If invoked on a very old system, the sort would be silently ignored and `head -1` would return an arbitrary tag rather than the latest semver — potentially installing an older version without warning.

**Fix:** Add a version check or post-fetch validation that the returned tag matches a semver pattern.

---

### 🟢 BUG-6: `_debug_print_plan` enables `set -x` permanently (Informational)

`set -x` is enabled when `FARADAI_DEBUG=1` but never explicitly disabled. Since `_exec_docker_run` calls `exec` immediately after, this is functionally harmless — the trace only fires for a few lines before the process is replaced.

**Recommendation:** Add a comment documenting the intent, since the pattern looks like a mistake without it.

---

### 🟢 BUG-7: No validation that command args are recognised (Informational)

If a user runs `faradai foobar`, `"foobar"` ends up in `_CMD_ARGS` and is forwarded to `docker exec`. The container will fail with a "command not found" error rather than a helpful faradai-level message.

**Recommendation:** Validate the first `_CMD_ARG` against the known command set in `_dispatch_meta_commands` or a new validation function.

---

### 🟢 BUG-8: Race condition between `_resolve_container_state` and `docker exec` (Informational)

`_resolve_container_state` checks if the container is running, then `_maybe_attach_existing` acts on that information via `docker exec`. Between the check and exec, the container could stop. The resulting `docker exec` failure message is self-explanatory.

**Recommendation:** Acceptable as-is — this is an inherent TOCTOU issue in container management with no practical consequence.
