#!/usr/bin/env bats
#
# Function-level unit tests for faradai phase functions.
#
# These tests source the faradai script rather than executing it, which requires
# the source-vs-execute guard in the script:
#
#   if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
#
# Without that guard, sourcing the script would execute main() and replace
# the test process via 'exec docker run'. All tests here will fail until both
# the guard and the phase functions exist.

FARADAI="${BATS_TEST_DIRNAME}/../faradai"

setup() {
  export PATH="${BATS_TEST_DIRNAME}/helpers:${PATH}"
  export FARADAI_TRUST_DIR=1
  export FARADAI_ENABLE_SSH_AGENT=0
  export FARADAI_WORKDIR="${BATS_TEST_DIRNAME}"
  # Source the script to load function definitions without executing main.
  source "${FARADAI}"
}

# ── _init_defaults ─────────────────────────────────────────────────────────────

@test "_init_defaults: _MODE defaults to auto" {
  _init_defaults
  [ "${_MODE}" = "auto" ]
}

@test "_init_defaults: _CONTAINER_NAME defaults to faradai" {
  _init_defaults
  [ "${_CONTAINER_NAME}" = "faradai" ]
}

@test "_init_defaults: _CMD_ARGS defaults to empty array" {
  _init_defaults
  [ "${#_CMD_ARGS[@]}" -eq 0 ]
}

@test "_init_defaults: DOCKER_RUN_ARGS defaults to empty array" {
  _init_defaults
  [ "${#DOCKER_RUN_ARGS[@]}" -eq 0 ]
}

@test "_init_defaults: resets state when called a second time" {
  # Calling _init_defaults twice must produce clean state, not accumulate values.
  _MODE="attach"
  _CONTAINER_NAME="faradai-old"
  _CMD_ARGS=(bash --resume)
  DOCKER_RUN_ARGS=(--some-leftover-flag)
  _init_defaults
  [ "${_MODE}" = "auto" ]
  [ "${_CONTAINER_NAME}" = "faradai" ]
  [ "${#_CMD_ARGS[@]}" -eq 0 ]
  [ "${#DOCKER_RUN_ARGS[@]}" -eq 0 ]
}

@test "_init_defaults: _SSH_AGENT_APPROVED initialised to 0" {
  # _SSH_AGENT_APPROVED is listed in the # Writes block; verify it is reset.
  _SSH_AGENT_APPROVED=99
  _init_defaults
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
}

@test "_init_defaults: _SSH_AGENT_APPROVED reset to 0 on second call" {
  _init_defaults
  _SSH_AGENT_APPROVED=1
  _init_defaults
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
}

# ── _parse_cli_flags (sourced — asserts globals directly) ──────────────────────

@test "_parse_cli_flags: no args — mode=auto, name=faradai, CMD_ARGS empty" {
  _init_defaults
  _parse_cli_flags
  [ "${_MODE}" = "auto" ]
  [ "${_CONTAINER_NAME}" = "faradai" ]
  [ "${#_CMD_ARGS[@]}" -eq 0 ]
}

@test "_parse_cli_flags: -a -n foo — mode=attach, name=faradai-foo, CMD_ARGS empty" {
  _init_defaults
  _parse_cli_flags -a -n foo
  [ "${_MODE}" = "attach" ]
  [ "${_CONTAINER_NAME}" = "faradai-foo" ]
  [ "${#_CMD_ARGS[@]}" -eq 0 ]
}

@test "_parse_cli_flags: -c bash — mode=create, CMD_ARGS=(bash)" {
  _init_defaults
  _parse_cli_flags -c bash
  [ "${_MODE}" = "create" ]
  [ "${_CMD_ARGS[0]}" = "bash" ]
  [ "${#_CMD_ARGS[@]}" -eq 1 ]
}

@test "_parse_cli_flags: claude --resume — mode=auto, CMD_ARGS=(claude --resume)" {
  _init_defaults
  _parse_cli_flags claude --resume
  [ "${_MODE}" = "auto" ]
  [ "${_CMD_ARGS[0]}" = "claude" ]
  [ "${_CMD_ARGS[1]}" = "--resume" ]
  [ "${#_CMD_ARGS[@]}" -eq 2 ]
}

@test "_parse_cli_flags: -a bash --some-arg — attach mode, full CMD_ARGS preserved" {
  _init_defaults
  _parse_cli_flags -a bash --some-arg
  [ "${_MODE}" = "attach" ]
  [ "${_CMD_ARGS[0]}" = "bash" ]
  [ "${_CMD_ARGS[1]}" = "--some-arg" ]
}

# ── _dispatch_meta_commands ────────────────────────────────────────────────────

@test "_dispatch_meta_commands: version exits 0 with version string" {
  run _dispatch_meta_commands version
  [ "$status" -eq 0 ]
  [[ "$output" == *"faradai"* ]]
}

@test "_dispatch_meta_commands: --version exits 0 with version string" {
  run _dispatch_meta_commands --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"faradai"* ]]
}

@test "_dispatch_meta_commands: help exits 0 with usage text" {
  run _dispatch_meta_commands help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "_dispatch_meta_commands: --help exits 0 with usage text" {
  run _dispatch_meta_commands --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "_dispatch_meta_commands: -h exits 0 with usage text" {
  run _dispatch_meta_commands -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "_dispatch_meta_commands: non-meta command returns 0 (falls through)" {
  run _dispatch_meta_commands bash
  [ "$status" -eq 0 ]
}

@test "_dispatch_meta_commands: empty arg returns 0 (falls through)" {
  run _dispatch_meta_commands ""
  [ "$status" -eq 0 ]
}

# ── _maybe_attach_existing ─────────────────────────────────────────────────────
#
# _CONTAINER_RUNNING is set directly here rather than via docker inspect —
# that's _resolve_container_state's job. These tests exercise the branching
# logic in isolation without needing docker mock enhancements.

@test "_maybe_attach_existing: create mode + running — returns 0 (no exec)" {
  # Create mode must never auto-attach, even if the container is already running.
  _init_defaults
  _MODE="create"
  _CONTAINER_RUNNING="true"
  run _maybe_attach_existing
  [ "$status" -eq 0 ]
}

@test "_maybe_attach_existing: create mode + not running — returns 0 (no exec)" {
  _init_defaults
  _MODE="create"
  _CONTAINER_RUNNING=""
  run _maybe_attach_existing
  [ "$status" -eq 0 ]
}

@test "_maybe_attach_existing: auto mode + not running — returns 0 (falls through to create)" {
  _init_defaults
  _MODE="auto"
  _CONTAINER_RUNNING=""
  run _maybe_attach_existing
  [ "$status" -eq 0 ]
}

@test "_maybe_attach_existing: auto mode + running — execs into container (mock exits 0)" {
  _init_defaults
  _MODE="auto"
  _CONTAINER_RUNNING="true"
  run _maybe_attach_existing
  [ "$status" -eq 0 ]
}

@test "_maybe_attach_existing: attach mode + running — execs into container (mock exits 0)" {
  _init_defaults
  _MODE="attach"
  _CONTAINER_RUNNING="true"
  run _maybe_attach_existing
  [ "$status" -eq 0 ]
}

@test "_maybe_attach_existing: attach mode + not running — exits 1 with default container name" {
  _init_defaults
  _MODE="attach"
  _CONTAINER_RUNNING=""
  _CONTAINER_NAME="faradai"
  run _maybe_attach_existing
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "_maybe_attach_existing: attach mode + not running — exits 1 with named container name" {
  _init_defaults
  _MODE="attach"
  _CONTAINER_RUNNING=""
  _CONTAINER_NAME="faradai-myproject"
  run _maybe_attach_existing
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai-myproject'"* ]]
}

# ── _resolve_workdir ───────────────────────────────────────────────────────────

@test "_resolve_workdir: valid existing directory — returns 0" {
  FARADAI_WORKDIR="${BATS_TEST_DIRNAME}"
  run _resolve_workdir
  [ "$status" -eq 0 ]
}

@test "_resolve_workdir: non-existent directory — exits 1 with error" {
  FARADAI_WORKDIR="/tmp/faradai-test-nonexistent-$$"
  run _resolve_workdir
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "_resolve_workdir: unset FARADAI_WORKDIR — defaults to current directory" {
  unset FARADAI_WORKDIR
  run _resolve_workdir
  [ "$status" -eq 0 ]
}

@test "_resolve_workdir: relative path — normalized to absolute" {
  local sub="${BATS_TEST_TMPDIR}/rw-reltest-$$"
  mkdir -p "${sub}"
  cd "${BATS_TEST_TMPDIR}"
  FARADAI_WORKDIR="rw-reltest-$$"
  _resolve_workdir
  [[ "${FARADAI_WORKDIR}" == /* ]]
  [[ "${FARADAI_WORKDIR}" == "${sub}" ]]
}

@test "_resolve_workdir: symlink — resolved to real path via pwd -P" {
  local real="${BATS_TEST_TMPDIR}/rw-real-$$"
  local link="${BATS_TEST_TMPDIR}/rw-link-$$"
  mkdir -p "${real}"
  ln -s "${real}" "${link}"
  FARADAI_WORKDIR="${link}"
  _resolve_workdir
  [[ "${FARADAI_WORKDIR}" == "${real}" ]]
}

# ── _dispatch_docker_metadata_commands ────────────────────────────────────────

@test "_dispatch_docker_metadata_commands: logs — calls docker logs (mock exits 0)" {
  _init_defaults
  run _dispatch_docker_metadata_commands logs
  [ "$status" -eq 0 ]
}

@test "_dispatch_docker_metadata_commands: status — calls docker inspect (mock exits 0)" {
  _init_defaults
  run _dispatch_docker_metadata_commands status
  [ "$status" -eq 0 ]
}

@test "_dispatch_docker_metadata_commands: non-metadata command — returns 0 (falls through)" {
  _init_defaults
  run _dispatch_docker_metadata_commands bash
  [ "$status" -eq 0 ]
}

# ── _load_runtime_config ───────────────────────────────────────────────────────

@test "_load_runtime_config: sets FARADAI_MEMORY default when unset" {
  unset FARADAI_MEMORY
  _load_runtime_config
  [ "${FARADAI_MEMORY}" = "4g" ]
}

@test "_load_runtime_config: sets FARADAI_CPUS default when unset" {
  unset FARADAI_CPUS
  _load_runtime_config
  [ "${FARADAI_CPUS}" = "4" ]
}

@test "_load_runtime_config: sets FARADAI_PIDS default when unset" {
  unset FARADAI_PIDS
  _load_runtime_config
  [ "${FARADAI_PIDS}" = "512" ]
}

@test "_load_runtime_config: sets FARADAI_NETWORK_MODE default when unset" {
  unset FARADAI_NETWORK_MODE
  _load_runtime_config
  [ "${FARADAI_NETWORK_MODE}" = "open" ]
}

@test "_load_runtime_config: preserves caller-supplied FARADAI_MEMORY" {
  export FARADAI_MEMORY="2g"
  _load_runtime_config
  [ "${FARADAI_MEMORY}" = "2g" ]
}

@test "_load_runtime_config: preserves caller-supplied FARADAI_NETWORK_MODE" {
  export FARADAI_NETWORK_MODE="none"
  _load_runtime_config
  [ "${FARADAI_NETWORK_MODE}" = "none" ]
}

# ── Pass 3 helpers ─────────────────────────────────────────────────────────────

# _args_include VALUE
# Returns 0 if VALUE is an element of DOCKER_RUN_ARGS, 1 otherwise.
# Exact match only — avoids false positives from substring checks.
_args_include() {
  local needle="$1" elem
  for elem in "${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"}"; do
    [[ "${elem}" == "${needle}" ]] && return 0
  done
  return 1
}

# _arg_index VALUE
# Prints the index of VALUE in DOCKER_RUN_ARGS, or exits 1 if not found.
_arg_index() {
  local needle="$1" i
  for i in "${!DOCKER_RUN_ARGS[@]}"; do
    [[ "${DOCKER_RUN_ARGS[$i]}" == "${needle}" ]] && { echo "${i}"; return 0; }
  done
  return 1
}

# _setup_fake_home
# Creates a minimal home directory structure in BATS_TEST_TMPDIR that
# satisfies _append_credential_mount_args without touching real home files.
_setup_fake_home() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.claude" "${HOME}/.config/gh"
  touch "${HOME}/.claude/.credentials.json" "${HOME}/.claude.json" \
        "${HOME}/.gitconfig"
}

# _make_test_repo DIR TAG
# Creates a minimal git repo at DIR with one empty commit tagged TAG.
# Uses lightweight tags (git tag, not git tag -a) — no peeled ^{} refs.
_make_test_repo() {
  local dir="${1}" tag="${2}"
  git init -q "${dir}"
  git -C "${dir}" config user.email "test@faradai.test"
  git -C "${dir}" config user.name "Faradai Test"
  git -C "${dir}" commit -q --allow-empty -m "init"
  git -C "${dir}" tag "${tag}"
}

# _setup_canon
# Initialise all globals to a canonical state for integration tests.
_setup_canon() {
  _init_defaults
  export FARADAI_WORKDIR="${BATS_TEST_TMPDIR}"
  export FARADAI_MEMORY=4g FARADAI_CPUS=4 FARADAI_PIDS=512
  export FARADAI_NETWORK_MODE=open
  _load_runtime_config
  _setup_fake_home
}

# -- _prompt_yes_no -----------------------------------------------------------

@test "_prompt_yes_no: non-interactive stdin -- dies with message" {
  run bash -c "source '${FARADAI}'; _prompt_yes_no 'mount /dir?'" <<< "y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"interactive confirmation required"* ]]
}

@test "_prompt_yes_no: answer y -- returns 0" {
  _is_interactive() { return 0; }
  _prompt_yes_no "test prompt?" < <(printf 'y\n')
}

@test "_prompt_yes_no: answer Y -- returns 0" {
  _is_interactive() { return 0; }
  _prompt_yes_no "test prompt?" < <(printf 'Y\n')
}

@test "_prompt_yes_no: answer n -- returns non-zero" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_yes_no 'test prompt?'
  " <<< "n"
  [ "$status" -ne 0 ]
}

@test "_prompt_yes_no: empty answer -- returns non-zero" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_yes_no 'test prompt?'
  " <<< ""
  [ "$status" -ne 0 ]
}

@test "_prompt_yes_no: EOF on stdin -- dies with message" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_yes_no 'test prompt?'
  " < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to read user input"* ]]
}

# -- _prompt_choice ------------------------------------------------------------

@test "_prompt_choice: non-interactive stdin -- dies with message" {
  run bash -c "source '${FARADAI}'; _prompt_choice 'Choose:' 'Option A' 'Option B'" <<< "1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"interactive selection required"* ]]
}

@test "_prompt_choice: choice 1 of 2 -- prints 0 to stdout" {
  _is_interactive() { return 0; }
  local result
  result="$(_prompt_choice "Choose:" "Option A" "Option B" < <(printf '1\n'))"
  [ "${result}" = "0" ]
}

@test "_prompt_choice: choice 2 of 2 -- prints 1 to stdout" {
  _is_interactive() { return 0; }
  local result
  result="$(_prompt_choice "Choose:" "Option A" "Option B" < <(printf '2\n'))"
  [ "${result}" = "1" ]
}

@test "_prompt_choice: choice 0 (out of range) -- dies" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_choice 'Choose:' 'Option A' 'Option B'
  " <<< "0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid selection"* ]]
}

@test "_prompt_choice: choice 3 of 2 (out of range) -- dies" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_choice 'Choose:' 'Option A' 'Option B'
  " <<< "3"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid selection"* ]]
}

@test "_prompt_choice: non-numeric input -- dies" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_choice 'Choose:' 'Option A' 'Option B'
  " <<< "abc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid selection"* ]]
}

@test "_prompt_choice: EOF on stdin -- dies" {
  run bash -c "
    source '${FARADAI}'
    _is_interactive() { return 0; }
    _prompt_choice 'Choose:' 'Option A' 'Option B'
  " < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to read user input"* ]]
}

# -- _confirm_trust_workdir ----------------------------------------------------

@test "_confirm_trust_workdir: FARADAI_TRUST_DIR=1 -- skips prompt, returns 0" {
  export FARADAI_TRUST_DIR=1
  export FARADAI_WORKDIR="${BATS_TEST_TMPDIR}"
  _confirm_trust_workdir
}

@test "_confirm_trust_workdir: answer y -- returns 0" {
  export FARADAI_TRUST_DIR=0
  export FARADAI_WORKDIR="${BATS_TEST_TMPDIR}"
  _is_interactive() { return 0; }
  _confirm_trust_workdir < <(printf 'y\n')
}

@test "_confirm_trust_workdir: answer n -- exits 0 with aborted message" {
  run bash -c "
    source '${FARADAI}'
    export FARADAI_TRUST_DIR=0
    export FARADAI_WORKDIR='${BATS_TEST_TMPDIR}'
    _is_interactive() { return 0; }
    _confirm_trust_workdir
  " <<< "n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aborted"* ]]
}

@test "_confirm_trust_workdir: non-interactive, FARADAI_TRUST_DIR=0 -- dies naming var" {
  run bash -c "
    source '${FARADAI}'
    export FARADAI_TRUST_DIR=0
    export FARADAI_WORKDIR='${BATS_TEST_TMPDIR}'
    _confirm_trust_workdir
  " <<< "y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FARADAI_TRUST_DIR"* ]]
}


# ── _handle_ssh_agent_forwarding ───────────────────────────���──────────────────

@test "_handle_ssh_agent_forwarding: FARADAI_ENABLE_SSH_AGENT=0 — skips, _SSH_AGENT_APPROVED stays 0" {
  _init_defaults
  export FARADAI_ENABLE_SSH_AGENT=0
  _handle_ssh_agent_forwarding
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
}

@test "_handle_ssh_agent_forwarding: no SSH_AUTH_SOCK set — skips, _SSH_AGENT_APPROVED stays 0" {
  _init_defaults
  export FARADAI_ENABLE_SSH_AGENT=1
  unset SSH_AUTH_SOCK
  _handle_ssh_agent_forwarding
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
}

@test "_handle_ssh_agent_forwarding: SSH_AUTH_SOCK set but not a socket — skips" {
  _init_defaults
  export FARADAI_ENABLE_SSH_AGENT=1
  export SSH_AUTH_SOCK="${BATS_TEST_TMPDIR}/not-a-socket"
  touch "${SSH_AUTH_SOCK}"   # regular file, not a socket
  _handle_ssh_agent_forwarding
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
}

@test "_handle_ssh_agent_forwarding: valid socket + FARADAI_TRUST_SSH_AGENT=1 — auto-approves without prompt" {
  _init_defaults
  local sock="${BATS_TEST_TMPDIR}/ssh-agent-$$.sock"
  python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX)
s.bind('${sock}')
s.listen(1)
time.sleep(5)
" &
  local _spid=$!
  sleep 0.1

  export FARADAI_ENABLE_SSH_AGENT=1 FARADAI_TRUST_SSH_AGENT=1
  export SSH_AUTH_SOCK="${sock}"
  _handle_ssh_agent_forwarding
  [ "${_SSH_AGENT_APPROVED}" -eq 1 ]

  kill "${_spid}" 2>/dev/null || true
}

@test "_handle_ssh_agent_forwarding: valid socket + user answers y — sets _SSH_AGENT_APPROVED=1" {
  _init_defaults
  local sock="${BATS_TEST_TMPDIR}/ssh-agent-y-$$.sock"
  python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX)
s.bind('${sock}')
s.listen(1)
time.sleep(5)
" &
  local _spid=$!
  sleep 0.1

  export FARADAI_ENABLE_SSH_AGENT=1 FARADAI_TRUST_SSH_AGENT=0
  export SSH_AUTH_SOCK="${sock}"
  # Stub _is_interactive so _prompt_yes_no proceeds despite pipe stdin.
  # Process substitution keeps _handle_ssh_agent_forwarding in the current
  # shell so _SSH_AGENT_APPROVED is visible after the call.
  _is_interactive() { return 0; }
  _handle_ssh_agent_forwarding < <(echo "y")
  [ "${_SSH_AGENT_APPROVED}" -eq 1 ]

  kill "${_spid}" 2>/dev/null || true
}

@test "_handle_ssh_agent_forwarding: valid socket + user answers n — _SSH_AGENT_APPROVED stays 0" {
  _init_defaults
  local sock="${BATS_TEST_TMPDIR}/ssh-agent-n-$$.sock"
  python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX)
s.bind('${sock}')
s.listen(1)
time.sleep(5)
" &
  local _spid=$!
  sleep 0.1

  export FARADAI_ENABLE_SSH_AGENT=1 FARADAI_TRUST_SSH_AGENT=0
  export SSH_AUTH_SOCK="${sock}"
  # Stub _is_interactive so _prompt_yes_no proceeds despite pipe stdin.
  _is_interactive() { return 0; }
  _handle_ssh_agent_forwarding < <(echo "n")
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]

  kill "${_spid}" 2>/dev/null || true
}

# ── _handle_ssh_agent_forwarding → _append_credential_mount_args (ordering) ───
#
# Integration guard for the temporal dependency documented in both function
# headers: _SSH_AGENT_APPROVED must be set by _handle_ssh_agent_forwarding
# before _append_credential_mount_args reads it to build the socket mount.

@test "_handle_ssh_agent_forwarding → _append_credential_mount_args: approved socket is mounted" {
  _setup_canon
  local sock="${BATS_TEST_TMPDIR}/ssh-order-$$.sock"
  python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX)
s.bind('${sock}')
s.listen(1)
time.sleep(5)
" &
  local _spid=$!
  sleep 0.1

  export FARADAI_ENABLE_SSH_AGENT=1 FARADAI_TRUST_SSH_AGENT=1
  export SSH_AUTH_SOCK="${sock}"

  _handle_ssh_agent_forwarding
  _append_credential_mount_args

  kill "${_spid}" 2>/dev/null || true

  [ "${_SSH_AGENT_APPROVED}" -eq 1 ]
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/ssh-agent"* ]]
}

@test "_handle_ssh_agent_forwarding → _append_credential_mount_args: denied agent leaves socket unmounted" {
  # _SSH_AGENT_APPROVED=0 after _handle_ssh_agent_forwarding (no socket) means
  # _append_credential_mount_args must not add the SSH socket mount.
  _setup_canon
  export FARADAI_ENABLE_SSH_AGENT=0
  _handle_ssh_agent_forwarding
  _append_credential_mount_args
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *"/ssh-agent"* ]]
}

# ── _append_runtime_flags ──────────────────────────────────────────────────────

@test "_append_runtime_flags: adds -it" {
  _init_defaults; _append_runtime_flags
  _args_include "-it"
}

@test "_append_runtime_flags: adds --rm" {
  _init_defaults; _append_runtime_flags
  _args_include "--rm"
}

@test "_append_runtime_flags: adds --init" {
  _init_defaults; _append_runtime_flags
  _args_include "--init"
}

@test "_append_runtime_flags: adds --name followed by container name" {
  _init_defaults
  _CONTAINER_NAME="faradai-test"
  _append_runtime_flags
  _args_include "--name"
  local idx; idx="$(_arg_index "--name")"
  [ "${DOCKER_RUN_ARGS[$(( idx + 1 ))]}" = "faradai-test" ]
}

@test "_append_runtime_flags: adds managed label dev.faradai.managed=true" {
  _init_defaults; _append_runtime_flags
  _args_include "dev.faradai.managed=true"
}

@test "_append_runtime_flags: adds container-name label matching _CONTAINER_NAME" {
  _init_defaults
  _CONTAINER_NAME="faradai-myproject"
  _append_runtime_flags
  _args_include "dev.faradai.container-name=faradai-myproject"
}

# ── _append_resource_args ──────────────────────────────────────────────────────

@test "_append_resource_args: adds --memory with FARADAI_MEMORY value" {
  _setup_canon; _append_resource_args
  _args_include "--memory=4g"
}

@test "_append_resource_args: adds --cpus with FARADAI_CPUS value" {
  _setup_canon; _append_resource_args
  _args_include "--cpus=4"
}

@test "_append_resource_args: adds --pids-limit with FARADAI_PIDS value" {
  _setup_canon; _append_resource_args
  _args_include "--pids-limit=512"
}

@test "_append_resource_args: adds --shm-size=1g (always fixed)" {
  _setup_canon; _append_resource_args
  _args_include "--shm-size=1g"
}

# ── _append_security_args ──────────────────────────────────────────────────────

@test "_append_security_args: adds --cap-drop ALL" {
  _init_defaults; _append_security_args
  _args_include "--cap-drop"
  local idx; idx="$(_arg_index "--cap-drop")"
  [ "${DOCKER_RUN_ARGS[$(( idx + 1 ))]}" = "ALL" ]
}

@test "_append_security_args: adds --security-opt no-new-privileges:true" {
  _init_defaults; _append_security_args
  _args_include "--security-opt"
  local idx; idx="$(_arg_index "--security-opt")"
  [ "${DOCKER_RUN_ARGS[$(( idx + 1 ))]}" = "no-new-privileges:true" ]
}

# ── _append_network_args ───────────────────────────────────────────────────────

@test "_append_network_args: NETWORK_MODE=open — no --network flag added" {
  _setup_canon   # sets NETWORK_MODE=open and runs _load_runtime_config
  _append_network_args
  ! _args_include "--network"
}

@test "_append_network_args: NETWORK_MODE=none — adds --network none" {
  _init_defaults
  export FARADAI_NETWORK_MODE=none
  _load_runtime_config
  _append_network_args
  _args_include "--network"
  local idx; idx="$(_arg_index "--network")"
  [ "${DOCKER_RUN_ARGS[$(( idx + 1 ))]}" = "none" ]
}

# ── _ensure_host_dirs ─────────────────────────────────────────────────────────

@test "_ensure_host_dirs: creates ~/.claude when absent" {
  export HOME="${BATS_TEST_TMPDIR}/fresh-claude-home-$$"
  mkdir -p "${HOME}"
  [ ! -d "${HOME}/.claude" ]
  _ensure_host_dirs
  [ -d "${HOME}/.claude" ]
}

@test "_ensure_host_dirs: creates ~/.config/gh when absent" {
  export HOME="${BATS_TEST_TMPDIR}/fresh-home-$$"
  mkdir -p "${HOME}"
  # Confirm the dir does not exist before the call.
  [ ! -d "${HOME}/.config/gh" ]
  _ensure_host_dirs
  [ -d "${HOME}/.config/gh" ]
}

@test "_ensure_host_dirs: succeeds idempotently when dirs already exist" {
  export HOME="${BATS_TEST_TMPDIR}/existing-home-$$"
  mkdir -p "${HOME}/.claude" "${HOME}/.config/gh"
  run _ensure_host_dirs
  [ "$status" -eq 0 ]
}

# ── _maybe_mount_file ─────────────────────────────────────────────────────────

@test "_maybe_mount_file: file present — appends -v mount to DOCKER_RUN_ARGS" {
  _setup_canon
  local src="${BATS_TEST_TMPDIR}/mmf-present"
  touch "${src}"
  _maybe_mount_file "${src}" "/container/dst"
  [[ "${DOCKER_RUN_ARGS[*]}" == *"${src}:/container/dst"* ]]
}

@test "_maybe_mount_file: file absent — DOCKER_RUN_ARGS unchanged" {
  _setup_canon
  local before=("${DOCKER_RUN_ARGS[@]}")
  _maybe_mount_file "${BATS_TEST_TMPDIR}/mmf-absent" "/container/dst"
  [[ "${DOCKER_RUN_ARGS[*]}" == "${before[*]}" ]]
}

@test "_maybe_mount_file: mode suffix — appended as :mode on the mount" {
  _setup_canon
  local src="${BATS_TEST_TMPDIR}/mmf-mode"
  touch "${src}"
  _maybe_mount_file "${src}" "/container/dst" "ro"
  [[ "${DOCKER_RUN_ARGS[*]}" == *"${src}:/container/dst:ro"* ]]
}

# ── _append_credential_mount_args ──────────────────────────────────────────────

@test "_append_credential_mount_args: always mounts ~/.claude" {
  _setup_canon; _append_credential_mount_args
  _args_include "-v"
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.claude:"* ]]
}

@test "_append_credential_mount_args: ~/.claude/.credentials.json present — mount included read-only" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *".credentials.json:ro"* ]]
}

@test "_append_credential_mount_args: ~/.claude/.credentials.json absent — mount not included" {
  _setup_canon
  rm "${HOME}/.claude/.credentials.json"
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *".credentials.json"* ]]
}

@test "_append_credential_mount_args: ~/.claude.json present — mount included" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.claude.json:"* ]]
}

@test "_append_credential_mount_args: ~/.claude.json absent — mount not included" {
  _setup_canon
  rm "${HOME}/.claude.json"
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *"/.claude.json:"* ]]
}

@test "_append_credential_mount_args: ~/.gitconfig present — mount included read-only" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.gitconfig:"*":ro"* ]]
}

@test "_append_credential_mount_args: ~/.gitconfig absent — mount not included" {
  _setup_canon
  rm "${HOME}/.gitconfig"
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *"/.gitconfig:"* ]]
}

@test "_append_credential_mount_args: always mounts ~/.config/gh" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.config/gh:"* ]]
}

@test "_append_credential_mount_args: _SSH_AGENT_APPROVED=1 — SSH socket mount present" {
  _setup_canon
  _SSH_AGENT_APPROVED=1
  export SSH_AUTH_SOCK="${BATS_TEST_TMPDIR}/fake.sock"
  _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/ssh-agent"* ]]
}

@test "_append_credential_mount_args: _SSH_AGENT_APPROVED=0 — SSH socket mount absent" {
  _setup_canon
  _SSH_AGENT_APPROVED=0
  export SSH_AUTH_SOCK="${BATS_TEST_TMPDIR}/fake.sock"
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *"/ssh-agent"* ]]
}

@test "_append_credential_mount_args: FARADAI_MOUNT_SSH_DIR=1 — ~/.ssh mount present" {
  _setup_canon
  export FARADAI_MOUNT_SSH_DIR=1
  _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.ssh:"* ]]
}

@test "_append_credential_mount_args: FARADAI_MOUNT_SSH_DIR=0 — ~/.ssh mount absent" {
  _setup_canon
  export FARADAI_MOUNT_SSH_DIR=0
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *"/.ssh:"* ]]
}

@test "_append_credential_mount_args: ~/.aider.conf.yml present — aider mount included" {
  _setup_canon
  touch "${HOME}/.aider.conf.yml"
  _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *".aider.conf.yml:"* ]]
}

@test "_append_credential_mount_args: ~/.aider.conf.yml absent — aider mount not included" {
  _setup_canon   # _setup_fake_home does not create .aider.conf.yml
  _append_credential_mount_args
  ! [[ "${DOCKER_RUN_ARGS[*]}" == *".aider.conf.yml:"* ]]
}

# ── _append_project_mount_args ─────────────────────────────────────────────────

@test "_append_project_mount_args: adds -v WORKDIR:WORKDIR" {
  _setup_canon
  _append_project_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"${FARADAI_WORKDIR}:${FARADAI_WORKDIR}"* ]]
}

# ── _append_extra_docker_args ──────────────────────────────────────────────────

@test "_append_extra_docker_args: empty FARADAI_DOCKER_ARGS — DOCKER_RUN_ARGS unchanged" {
  _setup_canon
  local before="${#DOCKER_RUN_ARGS[@]}"
  unset FARADAI_DOCKER_ARGS
  _append_extra_docker_args
  [ "${#DOCKER_RUN_ARGS[@]}" -eq "${before}" ]
}

@test "_append_extra_docker_args: permitted flag appears in DOCKER_RUN_ARGS" {
  _setup_canon
  export FARADAI_DOCKER_ARGS="--env FOO=bar"
  _append_extra_docker_args
  _args_include "--env"
}

@test "_append_extra_docker_args: denied flag exits 1" {
  _setup_canon
  export FARADAI_DOCKER_ARGS="--volume /foo:/bar"
  run _append_extra_docker_args
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

# ── _build_docker_run_args (integration + ordering) ───────────────────────────

@test "_build_docker_run_args: --name appears before faradai:latest" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  local name_idx image_idx
  name_idx="$(_arg_index "--name")"
  image_idx="$(_arg_index "faradai:latest")"
  (( name_idx < image_idx ))
}

@test "_build_docker_run_args: -w WORKDIR appears immediately before faradai:latest" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  local w_idx image_idx
  w_idx="$(_arg_index "-w")"
  image_idx="$(_arg_index "faradai:latest")"
  # -w VALUE IMAGE — so image_idx should be w_idx + 2
  (( image_idx == w_idx + 2 ))
}

@test "_build_docker_run_args: CMD_ARGS appended after faradai:latest" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args claude --resume
  local image_idx last_idx
  image_idx="$(_arg_index "faradai:latest")"
  last_idx=$(( ${#DOCKER_RUN_ARGS[@]} - 1 ))
  [ "${DOCKER_RUN_ARGS[$(( image_idx + 1 ))]}" = "claude" ]
  [ "${DOCKER_RUN_ARGS[${last_idx}]}" = "--resume" ]
}

@test "_build_docker_run_args: security flags always present" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  _args_include "--cap-drop"
  _args_include "--security-opt"
}

@test "_build_docker_run_args: no --network flag when mode is open" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  ! _args_include "--network"
}

@test "_build_docker_run_args: --network none present when mode is none" {
  _init_defaults
  export FARADAI_NETWORK_MODE=none FARADAI_MEMORY=4g FARADAI_CPUS=4 FARADAI_PIDS=512
  _load_runtime_config
  _setup_fake_home
  export FARADAI_WORKDIR="${BATS_TEST_TMPDIR}"
  _build_docker_run_args
  _args_include "--network"
}

@test "_build_docker_run_args: all -v mounts appear before faradai:latest" {
  # Docker parses positionally: every -v must be in the OPTIONS section,
  # before IMAGE. A -v after the image would be treated as CMD_ARGS.
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  local image_idx i
  image_idx="$(_arg_index "faradai:latest")"
  for i in "${!DOCKER_RUN_ARGS[@]}"; do
    if [[ "${DOCKER_RUN_ARGS[$i]}" == "-v" ]] && (( i >= image_idx )); then
      echo "Found -v at index $i, at or after faradai:latest at ${image_idx}" >&2
      return 1
    fi
  done
}

@test "_build_docker_run_args: FARADAI_DOCKER_ARGS extra flags appear before faradai:latest" {
  # User-supplied extra flags (validated by _append_extra_docker_args) must
  # land in the OPTIONS section, not after IMAGE where they become CMD_ARGS.
  _setup_canon; _setup_fake_home
  export FARADAI_DOCKER_ARGS="--env FOO=bar"
  _build_docker_run_args
  local image_idx env_idx
  image_idx="$(_arg_index "faradai:latest")"
  env_idx="$(_arg_index "--env")"
  (( env_idx < image_idx ))
}

# ── _prepare_container_name_for_create ────────────────────────────────────────

@test "_prepare_container_name_for_create: attach mode — no error" {
  _init_defaults
  _MODE="attach"
  run _prepare_container_name_for_create
  [ "$status" -eq 0 ]
}

@test "_prepare_container_name_for_create: create mode, default name — hint is 'faradai -a'" {
  _init_defaults
  _MODE="create"
  _CONTAINER_NAME="faradai"
  run _prepare_container_name_for_create
  [ "$status" -eq 1 ]
  [[ "$output" == *"faradai -a"* ]]
  [[ "$output" != *"faradai -a -n"* ]]
}

@test "_prepare_container_name_for_create: create mode, named container — hint includes '-n NAME'" {
  _init_defaults
  _MODE="create"
  _CONTAINER_NAME="faradai-myproj"
  run _prepare_container_name_for_create
  [ "$status" -eq 1 ]
  [[ "$output" == *"faradai -a -n myproj"* ]]
}

# ── _remove_stale_container ────────────────────────────────────────────────────

@test "_remove_stale_container: _CONTAINER_RUNNING empty — returns 0 silently" {
  _init_defaults
  _CONTAINER_RUNNING=""
  run _remove_stale_container
  [ "$status" -eq 0 ]
}

@test "_remove_stale_container: _CONTAINER_RUNNING true — returns 0 silently (running, skip)" {
  _init_defaults
  _CONTAINER_RUNNING="true"
  run _remove_stale_container
  [ "$status" -eq 0 ]
}

@test "_remove_stale_container: stopped container + user confirms — exits 0" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    _CONTAINER_RUNNING='false'
    _is_interactive() { return 0; }
    _remove_stale_container
  " <<< "y"
  [ "$status" -eq 0 ]
}

@test "_remove_stale_container: stopped container + user declines — dies" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    _CONTAINER_RUNNING='false'
    _is_interactive() { return 0; }
    _remove_stale_container
  " <<< "n"
  [ "$status" -eq 1 ]
}

@test "_remove_stale_container: stopped container + non-interactive — dies" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    _CONTAINER_RUNNING='false'
    _remove_stale_container
  " < /dev/null
  [ "$status" -eq 1 ]
}

@test "_remove_stale_container: stopped container — warns about state loss" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    _CONTAINER_RUNNING='false'
    _is_interactive() { return 0; }
    _remove_stale_container
  " <<< "n"
  [[ "$output" == *"container-local state will be lost"* ]]
}

# ── _preflight_credentials ────────────────────────────────────────────────────

@test "_preflight_credentials: non-AI boot target (bash) — returns 0, no recovery triggered" {
  _setup_fake_home
  rm "${HOME}/.claude/.credentials.json"  # creds absent — would trigger recovery if checked
  _init_defaults
  _CMD_ARGS=("bash")
  run _preflight_credentials
  [ "$status" -eq 0 ]
  [[ "$output" != *"choose an option"* ]]
  [[ "$output" != *"switching to"* ]]
}

@test "_preflight_credentials: both creds present, default target — returns 0 silently" {
  _setup_fake_home
  touch "${HOME}/.aider.conf.yml"
  _init_defaults
  run _preflight_credentials
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_preflight_credentials: both creds present, boot aider — returns 0 silently" {
  _setup_fake_home
  touch "${HOME}/.aider.conf.yml"
  _init_defaults
  _CMD_ARGS=("aider")
  run _preflight_credentials
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_preflight_credentials: claude creds missing — warns even when booting aider" {
  _setup_fake_home
  rm "${HOME}/.claude/.credentials.json"
  touch "${HOME}/.aider.conf.yml"
  _init_defaults
  _CMD_ARGS=("aider")
  run _preflight_credentials
  [ "$status" -eq 0 ]
  [[ "$output" == *"Claude credentials not found"* ]]
}

@test "_preflight_credentials: aider conf missing — warns even when booting claude" {
  _setup_fake_home
  _init_defaults
  _CMD_ARGS=("claude")
  run _preflight_credentials
  [ "$status" -eq 0 ]
  [[ "$output" == *"aider configuration not found"* ]]
}

@test "_preflight_credentials: claude creds missing, non-interactive — dies" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    export HOME='${BATS_TEST_TMPDIR}/pc-ni-home'
    mkdir -p \"\${HOME}/.claude\"
    _CMD_ARGS=('claude')
    _preflight_credentials
  " < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"credentials missing"* ]]
}

@test "_preflight_credentials: claude creds missing, aider present, picks aider — switches and drops extra flags" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    export HOME='${BATS_TEST_TMPDIR}/pc-sw-home'
    mkdir -p \"\${HOME}/.claude\"
    touch \"\${HOME}/.aider.conf.yml\"
    _CMD_ARGS=('claude' '--resume')
    _is_interactive() { return 0; }
    _preflight_credentials
    printf 'CMD:%s\n' \"\${_CMD_ARGS[@]}\"
  " <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"switching to aider"* ]]
  [[ "$output" == *"--resume"* ]]
  [[ "$output" == *"CMD:aider"* ]]
}

@test "_preflight_credentials: claude creds missing, aider present, picks bash — switches to bash" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    export HOME='${BATS_TEST_TMPDIR}/pc-bash-home'
    mkdir -p \"\${HOME}/.claude\"
    touch \"\${HOME}/.aider.conf.yml\"
    _CMD_ARGS=('claude')
    _is_interactive() { return 0; }
    _preflight_credentials
    printf 'CMD:%s\n' \"\${_CMD_ARGS[@]}\"
  " <<< "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CMD:bash"* ]]
}

@test "_preflight_credentials: both creds missing, picks bash — switches to bash" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    export HOME='${BATS_TEST_TMPDIR}/pc-none-home'
    mkdir -p \"\${HOME}/.claude\"
    _CMD_ARGS=('claude')
    _is_interactive() { return 0; }
    _preflight_credentials
    printf 'CMD:%s\n' \"\${_CMD_ARGS[@]}\"
  " <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CMD:bash"* ]]
}

@test "_preflight_credentials: aider conf missing, claude present, picks claude — switches and drops extra flags" {
  run bash -c "
    source '${FARADAI}'
    _init_defaults
    export HOME='${BATS_TEST_TMPDIR}/pc-aider-home'
    mkdir -p \"\${HOME}/.claude\"
    touch \"\${HOME}/.claude/.credentials.json\"
    _CMD_ARGS=('aider' '--no-git')
    _is_interactive() { return 0; }
    _preflight_credentials
    printf 'CMD:%s\n' \"\${_CMD_ARGS[@]}\"
  " <<< "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"switching to claude"* ]]
  [[ "$output" == *"--no-git"* ]]
  [[ "$output" == *"CMD:claude"* ]]
}

# ── _exec_docker_run ───────────────────────────────────────────────────────────

@test "_exec_docker_run: execs docker run with DOCKER_RUN_ARGS (mock exits 0)" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  run _exec_docker_run
  [ "$status" -eq 0 ]
}

# ── _verify_update_tag ────────────────────────────────────────────────────────

@test "_verify_update_tag: HEAD carries the expected tag — returns 0" {
  local repo="${BATS_TEST_TMPDIR}/vut-match-$$"
  _make_test_repo "${repo}" "v1.2.3"
  run _verify_update_tag "${repo}" "v1.2.3"
  [ "$status" -eq 0 ]
}

@test "_verify_update_tag: HEAD carries a different tag — exits 1 with expected/got message" {
  local repo="${BATS_TEST_TMPDIR}/vut-mismatch-$$"
  _make_test_repo "${repo}" "v1.2.3"
  run _verify_update_tag "${repo}" "v9.9.9"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected 'v9.9.9'"* ]]
  [[ "$output" == *"got 'v1.2.3'"* ]]
}

@test "_verify_update_tag: HEAD has no tag — exits 1 with 'not a tagged commit'" {
  local repo="${BATS_TEST_TMPDIR}/vut-notag-$$"
  git init -q "${repo}"
  git -C "${repo}" config user.email "test@faradai.test"
  git -C "${repo}" config user.name "Faradai Test"
  git -C "${repo}" commit -q --allow-empty -m "init"
  run _verify_update_tag "${repo}" "v1.0.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a tagged commit"* ]]
}

# ── _resolve_latest_tag ────────────────────────────────────────────────────────

@test "_resolve_latest_tag: single v* tag — returns that tag" {
  local repo="${BATS_TEST_TMPDIR}/rlt-one-$$"
  _make_test_repo "${repo}" "v0.1.0"
  local result
  result="$(_resolve_latest_tag "${repo}")"
  [ "${result}" = "v0.1.0" ]
}

@test "_resolve_latest_tag: multiple v* tags — returns the highest semver tag" {
  local repo="${BATS_TEST_TMPDIR}/rlt-multi-$$"
  git init -q "${repo}"
  git -C "${repo}" config user.email "test@faradai.test"
  git -C "${repo}" config user.name "Faradai Test"
  git -C "${repo}" commit -q --allow-empty -m "v1"
  git -C "${repo}" tag v0.1.0
  git -C "${repo}" commit -q --allow-empty -m "v2"
  git -C "${repo}" tag v0.9.0
  git -C "${repo}" commit -q --allow-empty -m "v3"
  git -C "${repo}" tag v0.2.0
  local result
  result="$(_resolve_latest_tag "${repo}")"
  [ "${result}" = "v0.9.0" ]
}

@test "_resolve_latest_tag: no v* tags — returns 1" {
  local repo="${BATS_TEST_TMPDIR}/rlt-notags-$$"
  git init -q "${repo}"
  git -C "${repo}" config user.email "test@faradai.test"
  git -C "${repo}" config user.name "Faradai Test"
  git -C "${repo}" commit -q --allow-empty -m "init"
  run _resolve_latest_tag "${repo}"
  [ "$status" -eq 1 ]
}
