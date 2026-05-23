# FaradAI CLI Refactor — Phase Pipeline

**Status:** complete — all three passes landed in session 42 (2026-05-23)
**Scope:** `faradai` script only (the launcher in repo root)
**Owner:** Josiah; plan authored by Claude (Sonnet 4.6)
**Related:** ROADMAP #40 (Rash migration) — explicitly *not* this work; this is a Bash-internal cleanup that should make a future Rash port easier, not harder

---

## Goal

Convert the bottom half of `faradai` (lines ~230–433) from a single 200-line top-level procedure into a **phase pipeline**: a small `main()` that calls a sequence of single-purpose functions, each with a narrow, documented contract.

After this refactor, reading `faradai` should mean reading `main()` once and following named phases, not tracing mutable globals down a flat script.

## Non-goals

- Not rewriting the script in another language (Rash, Python). Tracked separately in #40.
- Not making functions "pure." Bash arrays don't pass cleanly; documented globals are the idiom.
- Not changing observable CLI behaviour (with two opt-in exceptions in "Open decisions" below).
- Not touching the top-half function library (`_validate_*`, `_update_faradai`, `_check_image_user`, etc.) — already in good shape.
- Not introducing JSON/TOML config or a config-object pattern.

## Motivating problems

1. **No `main()`.** Bottom half lives at top-level scope; every assignment is implicit script API.
2. **Split subcommand dispatch is hidden ordering.** Two `case` statements split around docker pre-flight (lines 269–285, 292–302). The ordering invariant (`help`/`version`/`update`/`uninstall` don't need docker; `logs`/`status` do) is load-bearing but unnamed.
3. **`$USER` ordering bug** — latent, real. `_check_image_user` at line 305 compares the image label against `${USER}`, but `USER="${USER:-$(whoami)}"` doesn't run until line 373. If `$USER` is empty (rare interactive case, but possible under cron/minimal-shell contexts), the check produces a false-positive mismatch error. Fix during Pass 2.
4. **Interactive prompts tangled with config.** Trust-dir prompt (336–340) and SSH-agent prompt (382–394) sit inside what looks like mount-array assembly.
5. **Final `docker run` is coupled to every builder.** The exec at 411–433 splices `NETWORK_ARGS`, `GH_CONFIG_ARGS`, `SSH_AGENT_ARGS`, `SSH_DIR_ARGS`, `AIDER_CONF_MOUNT`, `EXTRA_DOCKER_ARGS` directly. Adding a mount means editing both the builder and the exec splice — two-point change for one concept.

## Target shape

```bash
main() {
  _init_defaults

  _parse_cli "$@"
  _dispatch_meta_commands "${_CMD_ARGS[@]}"   # may exit (help/version/update/uninstall)

  _preflight_docker
  _dispatch_docker_metadata_commands "${_CMD_ARGS[@]}"   # may exit (logs/status)

  _ensure_image_ready                          # image exists + user matches
  _resolve_workdir
  _resolve_container_state
  _maybe_attach_existing "${_CMD_ARGS[@]}"     # may exec into running container

  _confirm_trust_boundaries                    # workdir trust + ssh-agent consent
  _prepare_container_name_for_create           # error if create + already exists
  _setup_cleanup_trap

  _load_runtime_config                         # defaults + validation
  _build_docker_run_args "${_CMD_ARGS[@]}"     # accumulates into DOCKER_RUN_ARGS

  _debug_print_plan
  _exec_docker_run
}

main "$@"
```

State surface (globals owned by phases):

| Global | Set by | Read by |
|--------|--------|---------|
| `USER` (normalised) | `_init_defaults` | everything downstream |
| `_MODE` | `_parse_cli` | `_maybe_attach_existing`, `_prepare_container_name_for_create` |
| `_CONTAINER_NAME` | `_parse_cli` | most downstream phases |
| `_CMD_ARGS` | `_parse_cli` | dispatchers, `_maybe_attach_existing`, `_build_docker_run_args` |
| `_CONTAINER_RUNNING` | `_resolve_container_state` | `_maybe_attach_existing` |
| `_SSH_AGENT_APPROVED` | `_confirm_trust_boundaries` | `_build_docker_run_args` |
| `FARADAI_*` (validated) | `_load_runtime_config` | `_build_docker_run_args` |
| `DOCKER_RUN_ARGS` | `_build_docker_run_args` | `_exec_docker_run` |

Each phase function gets a 1–2-line header comment naming its `Reads:` / `Writes:` globals.

---

## Testability unlocked by the refactor

The biggest *secondary* benefit of phase extraction (beyond readability) is that it makes function-level unit testing possible for the first time. Today every test is end-to-end against `${FARADAI}`; after Pass 2, individual phases can be exercised directly.

**Enabling change (small, add during Pass 2):** wrap the bottom-of-script entrypoint in a source-vs-execute guard:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

That single conditional makes `source faradai` safe — the file becomes a library of phase functions that tests can call directly without triggering the whole pipeline.

**New test categories this unlocks:**

| Test | Before refactor | After |
|------|-----------------|-------|
| "Given `-a -n foo`, parser sets `_MODE=attach` and `_CONTAINER_NAME=faradai-foo`" | Indirect — observe via error message string match | Direct — call `_parse_cli`, assert on globals |
| "Given `FARADAI_NETWORK_MODE=none`, `_build_docker_run_args` includes `--network none`" | Impossible — no way to inspect arg array; mock just exits 0 | Direct — call builder, grep `DOCKER_RUN_ARGS` for `--network` |
| "Given `_MODE=attach` and container not running, `_maybe_attach_existing` exits 1 with named error" | End-to-end with docker mock | Stub `_CONTAINER_RUNNING=""`, call function, assert exit/output. Routes around #49. |
| "Given the SSH agent socket is present and consent denied, no `-v ${SSH_AUTH_SOCK}` mount appears" | Impossible — prompt is `read -r` inline; mount inspection impossible | Direct — stub `_confirm_ssh_agent_forwarding` to set `_SSH_AGENT_APPROVED=0`, call builder, assert absence |
| Dispatcher routing for `help`/`version`/`logs`/`status` | Untested today | Call dispatcher directly, assert exit code or capture exec'd command |

The biggest win is **`DOCKER_RUN_ARGS` introspection**. Today there's no way to verify the script assembles the right docker invocation — we trust visual inspection and SMOKETEST.md. After Pass 3, every appender becomes precisely testable.

## Test surface — what we're working with

The suite at `test/unit.bats` is **end-to-end integration tests, not function-level unit tests**: every test runs `${FARADAI}` as a subprocess with mocked `docker` on `$PATH` and asserts on exit status + output. This shape is load-bearing for the refactor:

- **Good:** phase extraction (Pass 2) touches *internal* structure only. The tests don't probe internals, so most should keep passing unchanged.
- **Bad:** the docker mock at `test/helpers/docker` is minimal (always returns `inspect` = `"false"`, every other call exits 0). Tracked as ROADMAP #49. Several refactor regression tests we'd want require a richer mock.

**Coverage today:**

| Area | Tests | State |
|------|-------|-------|
| Flag parser (mutual exclusion, `-n NAME`, `-a` lookahead) | 5 | **stale — broken by this session's CLI work** |
| `_validate_memory` / `_validate_cpus` / `_validate_pids` / `_validate_network_mode` | 17 | passing; phase-extraction-safe |
| `_build_extra_docker_args` (allowlist policy) | 11 | passing; phase-extraction-safe |
| `_check_image_user` | 3 | passing; **does not cover the `$USER`-unset bug** |
| `update --branch` validation | 1 | passing |
| Dispatch (`help`/`version`/`logs`/`status`/`bash`/`claude`) | 0 | uncovered |
| Auto-attach branching | 0 | uncovered (would need mock enhancement) |
| New `-c` flag, `-a -n NAME`, `-c -n NAME`, new mutual-exclusion error | 0 | **net-new, owed by this session** |

## Sequencing — pre-work, then three independent passes

Each pass should land as its own PR, pass the bats suite, run clean against SMOKETEST.md, and be revertable in isolation.

### Pass 0 — Test catch-up (do first, independent of the refactor)

**Why:** the unit tests are stale from the CLI changes we just shipped. They must be green before any refactor pass starts, otherwise we can't tell new breakage from pre-existing breakage.

**Changes to `test/unit.bats`:**
- **Update line 18–28** (`-n and -a are mutually exclusive`): new error string is `"-a and -c are mutually exclusive"`. The case `-a -n foo` is now *valid* (attach to `faradai-foo`); replace this test with one that asserts `-a -c` (in both orderings) produces the new error.
- **Update line 45–49** (`-a consumes an unknown word as NAME`): inverted assertion. New parser does *not* consume words after `-a`; `faradai -a myproject` should now produce `"no running container 'faradai'"` and pass `myproject` through as a `_CMD_ARGS` token (which becomes `docker exec ... myproject` — the mock exits 0).
- **Line 36–43** (`-a does not consume a known command as NAME`): this test still passes as-written because the new behavior matches the old assertion. Consider renaming it to drop the "known command" qualifier since the underlying mechanism (the `_KNOWN_CMDS` list) is gone.
- **Add tests** for: `-c` alone, `-c -n NAME`, `-a -n NAME` against not-running container, and that `-n NAME` alone falls into auto mode (attach if running, create if not — needs mock enhancement for the running case; without it, assert it reaches the "create" path by checking it doesn't error out before SSH/trust prompts).

**Effort:** ~30 min. Mostly mechanical.

### Pass 1 — CLI parser cleanup

**Scope:** Lines 230–265.

**Changes:**
- Wrap current parsing into `_parse_cli`.
- Outputs only: `_MODE`, `_CONTAINER_NAME`, `_CMD_ARGS`.
- No reference to subcommand names — parser must not know what `aider`/`logs` mean. (The `_KNOWN_CMDS` coupling we removed this session must not creep back in.)
- Introduce `_die` helper for error-and-exit (used here and reused in later passes).

**Behavioural decisions deferred to "Open decisions" section:** long-form flags, `--` separator.

**Validation (existing tests):**
- All bats tests pass unchanged (assuming Pass 0 landed).
- Manual: `faradai`, `faradai -a`, `faradai -c`, `faradai -n foo`, `faradai -a -n foo`, `faradai -c -n foo`, `faradai bash`, `faradai claude --resume`.
- Run SMOKETEST.md inside a fresh container.

**New tests to add:**
- If long-form flags adopted: one happy-path test per flag (`--attach`, `--create`, `--name`), one test that mixes short and long (`-a --name foo` should equal `-a -n foo`).
- If `--` separator adopted: test that `faradai -- -c` passes `-c` as a `_CMD_ARGS` token rather than entering create mode.
- Test that `faradai -n foo` (no `-c`/`-a`) reaches the auto-mode code path (assert via a no-error/no-prompt run, since the mock can't simulate "already running" without #49).

**Docs to update:** none expected (we already updated README + `_usage` this session).

### Pass 2 — Phase extraction (`main()` + dispatch split + ordering bug fix)

**Scope:** Lines 267–354 and the `USER=` line at 373.

**Changes:**
- Introduce `_init_defaults` (sets `USER`, `_MODE`, `_CONTAINER_NAME`, `_CMD_ARGS`, `DOCKER_RUN_ARGS=()`). **Fixes the `$USER` ordering bug** by normalising before any downstream consumer.
- Extract `_dispatch_meta_commands`, `_preflight_docker`, `_dispatch_docker_metadata_commands`, `_ensure_image_ready`, `_resolve_workdir`, `_resolve_container_state`, `_maybe_attach_existing`, `_confirm_trust_boundaries` (containing `_confirm_workdir_mount` and `_confirm_ssh_agent_forwarding`), `_prepare_container_name_for_create`, `_setup_cleanup_trap`, `_load_runtime_config`.
- Introduce `main()` calling them in order. Last line of script becomes `main "$@"`.

**Decision to make during this pass:** should `_resolve_container_state` run unconditionally (one extra `docker inspect` on `-c`, simpler code) or only when `_MODE != create` (matches current behaviour)? Recommend **unconditional + document why** — cost is one process spawn, gain is one fewer branch in `main()`.

**Enabling change for testing:** wrap `main "$@"` in a source-vs-execute guard (see "Testability unlocked" section). This single conditional is what turns the script into a sourceable library for unit tests.

**Validation (existing tests):**
- Bats suite passes unchanged.
- SMOKETEST.md passes inside a fresh container.
- Manual check of attach/auto/create branching unchanged.

**New tests to add (priority order):**
1. **Regression test for the `$USER` bug** — `run env -u USER MOCK_IMAGE_USER=someone "${FARADAI}"` should not produce a false-positive `"image was built for user 'someone'"` mismatch error. This was unreachable before the fix; pin it down so future refactors can't regress it.
2. **Sourced-function tests** for `_parse_cli` — `source faradai; _parse_cli -a -n foo; [ "$_MODE" = attach ]; [ "$_CONTAINER_NAME" = faradai-foo ]`. Faster, more precise, no docker mock needed. Replaces several of the indirect parser tests over time.
3. **Sourced-function tests** for `_init_defaults` — verify `USER` falls back to `whoami` output, `_MODE` defaults to `auto`, `DOCKER_RUN_ARGS` initialized empty.
4. **Sourced-function tests** for `_maybe_attach_existing` with stubbed `_CONTAINER_RUNNING` — exercises the three-mode branching without requiring docker mock enhancements. This is the cleanest way around ROADMAP #49 for attach-path coverage.
5. **Dispatcher coverage** — `_dispatch_meta_commands version` should exit with version string; `_dispatch_meta_commands help` should print usage. Trivial to assert once dispatchers are functions.

**Docs to update:** DECISIONLOG entry for the `$USER` ordering fix (mention the latent bug, fix, and why the unconditional state-resolve choice).

### Pass 3 — `DOCKER_RUN_ARGS` builder extraction

**Scope:** Lines 358–433.

**Changes:**
- Replace per-category arrays (`NETWORK_ARGS`, `GH_CONFIG_ARGS`, `SSH_AGENT_ARGS`, `SSH_DIR_ARGS`, `AIDER_CONF_MOUNT`, `EXTRA_DOCKER_ARGS`) with a single accumulator `DOCKER_RUN_ARGS`.
- Introduce named appenders: `_append_runtime_flags`, `_append_resource_args`, `_append_security_args`, `_append_network_args`, `_append_credential_mount_args`, `_append_project_mount_args`, `_append_extra_docker_args`.
- `_build_docker_run_args` is the orchestrator that calls the appenders in order and finishes with `-w "${FARADAI_WORKDIR}" faradai:latest "$@"`.
- **Refactor `_build_extra_docker_args` to append to `DOCKER_RUN_ARGS` directly.** Do not preserve the intermediate `EXTRA_DOCKER_ARGS` array; no wrapper functions. Existing validation logic stays as-is, only the output target changes.
- `_exec_docker_run` becomes one line: `exec docker run "${DOCKER_RUN_ARGS[@]}"`.

**Validation (existing tests):**
- Bats suite passes unchanged.
- SMOKETEST.md passes inside a fresh container.
- Manual: launch with `FARADAI_DEBUG=1` and diff the resolved `docker run` invocation against pre-refactor output — must be byte-identical (modulo arg ordering, if any).
- Manual: verify all opt-in paths still work — `FARADAI_NETWORK_MODE=none`, `FARADAI_MOUNT_SSH_DIR=1`, `FARADAI_DOCKER_ARGS="-e FOO=bar"`, missing `~/.aider.conf.yml`, missing `SSH_AUTH_SOCK`.

**New tests to add — this is where the biggest testability win lives.** Today the `_build_extra_docker_args` tests at lines 192–262 are *the only* tests that probe arg-assembly logic, and even they assert only on script exit status. After Pass 3, every appender becomes precisely testable:

1. **Per-appender unit tests** (highest value):
   - `_append_resource_args` — given `FARADAI_MEMORY=2g FARADAI_CPUS=8`, assert `DOCKER_RUN_ARGS` contains `--memory=2g` and `--cpus=8`.
   - `_append_security_args` — always-on; assert `--cap-drop ALL` and `--security-opt no-new-privileges:true` are present.
   - `_append_network_args` — table-test: `FARADAI_NETWORK_MODE=open` → no `--network` flag; `=none` → `--network none` present.
   - `_append_credential_mount_args` — verify mount lines for `.claude`, `.claude.json`, `.gitconfig`, `gh/`. Stub `_SSH_AGENT_APPROVED=1` and assert SSH socket mount appears; stub `=0` and assert it doesn't.
   - `_append_project_mount_args` — given a specific `FARADAI_WORKDIR`, assert exact `-v WORKDIR:WORKDIR` line.
   - `_append_extra_docker_args` — keep existing allowlist tests (still valuable end-to-end), add direct-call tests asserting the appended args land in the accumulator.
2. **Full `_build_docker_run_args` integration** — call with a canonical env, assert the full `DOCKER_RUN_ARGS` array matches an expected sequence. This becomes the "golden" test that anchors the assembled invocation.
3. **Order-sensitivity guard** — assert `--name` appears before `faradai:latest`, the image appears before any trailing `$@` args. Catches accidental appender reordering during future edits.
4. **Replace the byte-diff manual check with an automated golden test** — capture `DOCKER_RUN_ARGS` for a representative invocation, commit it as a fixture, fail if the assembled args drift unexpectedly.

**Docs to update:** none expected — this is internal restructure with no observable behaviour change.

---

## Open decisions (resolve before Pass 1 starts)

1. **Long-form flags (`--attach`, `--create`, `--name`) in addition to short forms?**
   GPT suggested adding them. Pro: future-proofing, more discoverable, conventional Unix grammar. Con: scope creep, more surface to test, two ways to do the same thing. **Recommendation:** add them — cheap inside the same parser rewrite, and the asymmetry of "short-flag-only" is a wart we'd otherwise need to fix later.
   **Decision:** deferred. Not part of the phase refactor; better as a separate PR once structure is settled.

2. **`--` separator support in the parser?**
   GPT's draft handles `--` to mean "everything after this is COMMAND args, stop parsing FaradAI flags." Currently unsupported. Pro: lets users pass commands that look like FaradAI flags (`faradai claude -- --resume` is fine today, but `faradai -- -c-something-internal` isn't). Con: edge case nobody has hit. **Recommendation:** add it — same parser rewrite, no behavioural regression possible, costs one `case` arm.
   **Decision:** deferred. Same rationale as above.

3. **Should the refactor be tracked as a single ROADMAP issue or three?**
   Three sequenced PRs benefit from three issues (clear "Now" focus). Single issue with checkboxes also works. **Recommendation:** one umbrella issue + three PRs referencing it.

---

## Risks

- **Behavioural drift in attach detection.** The current `_is_running` check is subtle (uses `||` to clear the var when `docker inspect` fails). Easy to break during extraction. Mitigation: keep the exact `docker inspect ... || true` pattern in `_resolve_container_state`.
- **Bats coverage gaps.** Current tests may not exercise every path (#49 already tracks "docker mock too permissive"). If a phase extraction silently breaks an unmocked path, CI won't catch it. Mitigation: run SMOKETEST.md after each pass, not just bats.
- **Pass 3 cargo-culting.** Easy to accidentally reorder appender calls in a way that produces a different `docker run` arg sequence. Docker tolerates most reorderings, but `--name` and label/env interactions can be order-sensitive. Mitigation: byte-diff the `FARADAI_DEBUG=1` output before/after Pass 3.
- **Refactor competing with new features.** The roadmap has live issues (#59 just landed, #60–64 queued). Land the refactor passes between feature work, not interleaved, to keep diffs reviewable.

## What this refactor does *not* fix

- The validators-exit-directly coupling (intentional fail-fast, keeping it).
- The single-script monolith (no plan to split into multiple files in Bash; revisit if/when #40 lands).
- #49 (docker mock too permissive) is *not* directly fixed, but the sourceable-functions approach routes around it for most testing needs — function-level unit tests don't need the mock at all. #49 remains valuable for the remaining end-to-end tests that exercise dispatch + docker pre-flight in one go.
- #62 (pin bats-core to a tag) — separate, do anytime.

## Estimated effort

- Pass 1: ~1 short session. Mostly mechanical.
- Pass 2: ~2 sessions. Phase extraction is bulk of the work; `$USER` fix is small but needs a regression test.
- Pass 3: ~1 session. Mechanical once Pass 2 is in.

Total: 3–4 focused sessions, spread across whatever cadence fits other roadmap work.
