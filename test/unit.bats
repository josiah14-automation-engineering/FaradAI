#!/usr/bin/env bats

FARADAI="${BATS_TEST_DIRNAME}/../faradai"

setup() {
  # Prepend mock helpers so docker is intercepted before the real binary.
  export PATH="${BATS_TEST_DIRNAME}/helpers:${PATH}"
  # Bypass the directory trust prompt for all tests that reach it.
  export FARADAI_TRUST_DIR=1
  # Disable SSH agent forwarding to avoid host socket interference.
  export FARADAI_ENABLE_SSH_AGENT=0
  # Use a stable working directory that exists.
  export FARADAI_WORKDIR="${BATS_TEST_DIRNAME}"
  # Isolate from the real home directory so tests never read or write actual
  # agent config (~/.claude, ~/.codex, ~/.config/gh). Without this, _preflight_credentials
  # dies non-interactively in CI (no credentials file), and _ensure_host_dirs
  # could create directories inside real agent config on developer machines.
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/.claude" "${HOME}/.codex" "${HOME}/.config/gh"
  touch "${HOME}/.claude/.credentials.json"
  touch "${HOME}/.codex/auth.json"
}

# ── flag parser: mode flags (-a, -c) ──────────────────────────────────────────

@test "flag parser: no flags uses auto mode (reaches docker run)" {
  # Baseline: bare invocation reaches docker run (mock exits 0).
  run "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "flag parser: -c enters create mode" {
  # Mock inspect exits 0 (simulates pre-existing container); create mode must refuse.
  run "${FARADAI}" -c
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "flag parser: -a enters attach mode" {
  # Mock inspect returns 'false' (not running); attach mode must error.
  run "${FARADAI}" -a
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "flag parser: -a and -c are mutually exclusive (a then c)" {
  run "${FARADAI}" -a -c
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "flag parser: -a and -c are mutually exclusive (c then a)" {
  run "${FARADAI}" -c -a
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── flag parser: -n (name flag) ────────────────────────────────────────────────

@test "flag parser: -n NAME alone uses auto mode" {
  # -n sets the name only; without -a or -c mode stays auto, reaching docker run.
  # Mock inspect exits 0 but create-conflict check is skipped in auto mode.
  run "${FARADAI}" -n myproject
  [ "$status" -eq 0 ]
}

@test "flag parser: -n requires a NAME argument" {
  run "${FARADAI}" -n
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: -n followed by a flag-looking token is an error" {
  # -n's next token must be a plain NAME; a flag-looking token must be rejected.
  run "${FARADAI}" -n -a
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: -n with empty string NAME is an error" {
  run "${FARADAI}" -n ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: -n with whitespace-only NAME is an error" {
  run "${FARADAI}" -n "   "
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: -n with tab NAME is an error" {
  run "${FARADAI}" -n $'\t'
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: duplicate -n flags are an error" {
  run "${FARADAI}" -n foo -n bar
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n may only be specified once"* ]]
}

@test "flag parser: -n NAME with slash — invalid Docker name" {
  run "${FARADAI}" -n "my/project"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid container name"* ]]
}

@test "flag parser: -n NAME with space — invalid Docker name" {
  run "${FARADAI}" -n "my project"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid container name"* ]]
}

@test "flag parser: -n NAME with dots, underscores, dashes — valid Docker name" {
  run "${FARADAI}" -n "my.proj_ect-1"
  [ "$status" -eq 0 ]
}

# ── flag parser: flag combinations ─────────────────────────────────────────────

@test "flag parser: -c -n NAME enters create mode for named container" {
  run "${FARADAI}" -c -n myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"faradai-myproject"* ]]
  [[ "$output" == *"already exists"* ]]
}

@test "flag parser: -c -n NAME error hints correct attach syntax" {
  # Error message must use 'faradai -a -n NAME' syntax.
  run "${FARADAI}" -c -n myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"faradai -a -n myproject"* ]]
}

@test "flag parser: -n NAME -c and -c -n NAME are equivalent (order independent)" {
  # -n and -c are orthogonal; either order must produce the same result.
  run "${FARADAI}" -n myproject -c
  [ "$status" -eq 1 ]
  [[ "$output" == *"faradai-myproject"* ]]
  [[ "$output" == *"already exists"* ]]
}

@test "flag parser: -a -n NAME attaches to named container" {
  # Mock returns 'false' (not running); attach fails with the correct name.
  run "${FARADAI}" -a -n myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai-myproject'"* ]]
}

@test "flag parser: -a -n NAME with subcommand uses correct container name" {
  # Integration: attach + name + subcommand all interact correctly.
  run "${FARADAI}" -a -n myproject bash
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai-myproject'"* ]]
}

# ── flag parser: stop-at-first-non-flag ────────────────────────────────────────

@test "flag parser: -a does not consume any token as NAME" {
  # -a sets attach mode; the following token becomes CMD_ARGS, not the container name.
  # Attach fails referencing 'faradai' (not 'faradai-claude').
  run "${FARADAI}" -a claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "flag parser: -a myproject attaches to faradai, not faradai-myproject" {
  # Old parser consumed an unknown word after -a as the container name.
  # New parser does not — use -n to name the container.
  run "${FARADAI}" -a myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "flag parser: flags after subcommand are not processed" {
  # 'bash' is the first non-flag token; '-c' after it must not enter create mode.
  # Mode stays auto and docker run fires (mock exits 0).
  run "${FARADAI}" bash -c
  [ "$status" -eq 0 ]
}

@test "flag parser: -a after subcommand does not trigger attach mode" {
  # '-a' after 'bash' must not set attach mode.
  # Auto mode reaches docker run (mock exits 0).
  run "${FARADAI}" bash -a
  [ "$status" -eq 0 ]
}

# ── _check_image_user (USER ordering regression) ──────────────────────────────

@test "_check_image_user: no false positive when USER is unset and label matches whoami" {
  # Regression: _check_image_user used to run before USER was normalised via
  # ${USER:-$(whoami)}, so an unset USER caused a phantom mismatch.
  # After the fix, _init_defaults normalises USER early; this must exit 0.
  run env -u USER MOCK_IMAGE_USER="$(whoami)" "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── _validate_memory ───────────────────────────────────────────────────────────

@test "_validate_memory: rejects 0g" {
  run env FARADAI_MEMORY=0g "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"greater than zero"* ]]
}

@test "_validate_memory: rejects 0m" {
  run env FARADAI_MEMORY=0m "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"greater than zero"* ]]
}

@test "_validate_memory: rejects 0.0g" {
  run env FARADAI_MEMORY=0.0g "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"greater than zero"* ]]
}

@test "_validate_memory: accepts 0.5g" {
  run env FARADAI_MEMORY=0.5g "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_memory: rejects non-numeric" {
  run env FARADAI_MEMORY=abc "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_MEMORY"* ]]
}

@test "_validate_memory: rejects 513g (exceeds sanity limit)" {
  run env FARADAI_MEMORY=513g "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"512g sanity limit"* ]]
}

@test "_validate_memory: rejects 512.5g (decimal exceeds sanity limit)" {
  run env FARADAI_MEMORY=512.5g "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"512g sanity limit"* ]]
}

@test "_validate_memory: rejects 524288.5m (decimal exceeds sanity limit)" {
  run env FARADAI_MEMORY=524288.5m "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"512g sanity limit"* ]]
}

@test "_validate_memory: accepts 512g (at sanity limit)" {
  run env FARADAI_MEMORY=512g "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_memory: accepts 4g" {
  run env FARADAI_MEMORY=4g "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_memory: accepts 512m" {
  run env FARADAI_MEMORY=512m "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── _validate_cpus ─────────────────────────────────────────────────────────────

@test "_validate_cpus: rejects 0" {
  run env FARADAI_CPUS=0 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"greater than zero"* ]]
}

@test "_validate_cpus: rejects negative" {
  run env FARADAI_CPUS=-1 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_CPUS"* ]]
}

@test "_validate_cpus: rejects non-numeric" {
  run env FARADAI_CPUS=abc "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_CPUS"* ]]
}

@test "_validate_cpus: rejects 129 (exceeds limit)" {
  run env FARADAI_CPUS=129 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_CPUS"* ]]
}

@test "_validate_cpus: rejects 128.5 (decimal exceeds limit)" {
  run env FARADAI_CPUS=128.5 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_CPUS"* ]]
}

@test "_validate_cpus: accepts 4" {
  run env FARADAI_CPUS=4 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_cpus: accepts 2.5" {
  run env FARADAI_CPUS=2.5 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_cpus: accepts 128 (at limit)" {
  run env FARADAI_CPUS=128 "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── _validate_pids ─────────────────────────────────────────────────────────────

@test "_validate_pids: rejects 0" {
  run env FARADAI_PIDS=0 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"at least 1"* ]]
}

@test "_validate_pids: rejects non-integer" {
  run env FARADAI_PIDS=abc "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_PIDS"* ]]
}

@test "_validate_pids: rejects float" {
  run env FARADAI_PIDS=2.5 "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_PIDS"* ]]
}

@test "_validate_pids: accepts 512" {
  run env FARADAI_PIDS=512 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_pids: accepts 1" {
  run env FARADAI_PIDS=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── _validate_network_mode ─────────────────────────────────────────────────────

@test "_validate_network_mode: rejects unknown mode" {
  run env FARADAI_NETWORK_MODE=bridge "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid FARADAI_NETWORK_MODE"* ]]
}

@test "_validate_network_mode: accepts open" {
  run env FARADAI_NETWORK_MODE=open "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_validate_network_mode: accepts none" {
  run env FARADAI_NETWORK_MODE=none "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── _append_extra_docker_args ───────────────────────────────────────────────────

@test "_append_extra_docker_args: permits --env" {
  run env FARADAI_DOCKER_ARGS="--env FOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: permits -e" {
  run env FARADAI_DOCKER_ARGS="-e FOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: permits --label" {
  run env FARADAI_DOCKER_ARGS="--label app=test" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: permits --hostname" {
  run env FARADAI_DOCKER_ARGS="--hostname myhost" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: denies --volume" {
  run env FARADAI_DOCKER_ARGS="--volume /foo:/bar" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_append_extra_docker_args: denies --network" {
  run env FARADAI_DOCKER_ARGS="--network host" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_append_extra_docker_args: denies --device without opt-in" {
  run env FARADAI_DOCKER_ARGS="--device /dev/snd" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_append_extra_docker_args: permits --device with FARADAI_ALLOW_DEVICE=1" {
  run env FARADAI_DOCKER_ARGS="--device /dev/snd" FARADAI_ALLOW_DEVICE=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: denies --publish without opt-in" {
  run env FARADAI_DOCKER_ARGS="--publish 8080:80" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_append_extra_docker_args: permits --publish with FARADAI_ALLOW_PUBLISH=1" {
  run env FARADAI_DOCKER_ARGS="--publish 8080:80" FARADAI_ALLOW_PUBLISH=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: permits -p with FARADAI_ALLOW_PUBLISH=1" {
  run env FARADAI_DOCKER_ARGS="-p 8080:80" FARADAI_ALLOW_PUBLISH=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: permits combined short-flag form -eFOO=bar" {
  run env FARADAI_DOCKER_ARGS="-eFOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_append_extra_docker_args: denies combined unknown short flag -xFOO" {
  run env FARADAI_DOCKER_ARGS="-xFOO" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

# ── _check_image_user ─────────────────────────────────────────────────────────

@test "_check_image_user: passes when label matches runtime user" {
  run env MOCK_IMAGE_USER="testuser" USER="testuser" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_check_image_user: fails with clear error when label mismatches runtime user" {
  run env MOCK_IMAGE_USER="otheruser" USER="testuser" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"image was built for user 'otheruser'"* ]]
  [[ "$output" == *"rebuild with: ./install.sh"* ]]
}

@test "_check_image_user: skips silently when label is absent" {
  run "${FARADAI}"
  [ "$status" -eq 0 ]
}

# ── update subcommand ──────────────────────────────────────────────────────────

@test "update: --branch without NAME exits with error" {
  run "${FARADAI}" update --branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"--branch requires a name"* ]]
}

@test "flag parser: -v prints version and exits 0" {
  run "${FARADAI}" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"faradai"* ]]
}

@test "flag parser: -a -v prints version, not an attach error" {
  run "${FARADAI}" -a -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"faradai"* ]]
  [[ "$output" != *"no running container"* ]]
}

@test "uninstall: missing binary exits 1 with manual cleanup hint" {
  run env _UNINSTALL_BIN=/nonexistent/path "${FARADAI}" uninstall
  [ "$status" -eq 1 ]
  [[ "$output" == *"uninstall-faradai not found"* ]]
}

# ── _resolve_container_state (inspect failure paths) ──────────────────────────

@test "_resolve_container_state: inspect exit 1 clears running state; auto mode proceeds to docker run" {
  # MOCK_DOCKER_INSPECT_EXIT=1 simulates the container-not-found path.
  # _CONTAINER_RUNNING is cleared; auto mode finds nothing to attach and falls
  # through to docker run (mock exits 0).
  run env MOCK_DOCKER_INSPECT_EXIT=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_resolve_container_state: inspect exit 1; attach mode reports no running container" {
  # Same not-found condition, but -a requires a running container → must fail.
  run env MOCK_DOCKER_INSPECT_EXIT=1 "${FARADAI}" -a
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "_resolve_container_state: inspect exit 1 with -n NAME; attach mode reports correct container name" {
  # Error message must reference the resolved container name, not the bare name.
  run env MOCK_DOCKER_INSPECT_EXIT=1 "${FARADAI}" -a -n myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai-myproject'"* ]]
}

@test "_resolve_container_state: inspect returns 'true'; auto mode attaches to running container" {
  # MOCK_DOCKER_INSPECT_RUNNING=true → _CONTAINER_RUNNING="true".
  # _maybe_attach_existing fires exec docker exec; mock wildcard case exits 0.
  run env MOCK_DOCKER_INSPECT_RUNNING=true "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_resolve_container_state: inspect returns 'false'; auto mode prompts to remove stopped container" {
  # MOCK_DOCKER_INSPECT_RUNNING=false → _CONTAINER_RUNNING="false".
  # _remove_stale_container calls _prompt_yes_no, which requires an interactive
  # terminal; bats is non-interactive so _die fires with "interactive confirmation".
  run env MOCK_DOCKER_INSPECT_RUNNING=false "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"interactive confirmation required"* ]]
}

@test "_resolve_container_state: inspect exit 1; create mode sees no conflict and proceeds to docker run" {
  # _prepare_container_name_for_create calls docker inspect directly; exit 1
  # means the container does not exist, so create mode must proceed without error.
  run env MOCK_DOCKER_INSPECT_EXIT=1 "${FARADAI}" -c
  [ "$status" -eq 0 ]
}

# ── _debug_print_plan (FARADAI_DEBUG=1) ───────────────────────────────────────

@test "_debug_print_plan: FARADAI_DEBUG=1 warns that expanded variables may contain secrets" {
  run env FARADAI_DEBUG=1 "${FARADAI}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: debug mode active"* ]]
  [[ "$output" == *"secrets or API keys"* ]]
}

@test "_debug_print_plan: FARADAI_DEBUG=1 warns that AI agents transmit output to upstream servers" {
  run env FARADAI_DEBUG=1 "${FARADAI}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transmit it to upstream servers"* ]]
}

@test "_debug_print_plan: FARADAI_DEBUG=0 does not print debug warning" {
  run env FARADAI_DEBUG=0 "${FARADAI}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING: debug mode active"* ]]
}
