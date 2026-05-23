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

# ── _handle_ssh_agent_forwarding ──────────────────────────────────────────────

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
  # Process substitution keeps _handle_ssh_agent_forwarding in the current
  # shell so _SSH_AGENT_APPROVED is visible after the call.
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
  _handle_ssh_agent_forwarding < <(echo "n")
  [ "${_SSH_AGENT_APPROVED}" -eq 0 ]

  kill "${_spid}" 2>/dev/null || true
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

@test "_ensure_host_dirs: creates ~/.config/gh when absent" {
  export HOME="${BATS_TEST_TMPDIR}/fresh-home-$$"
  mkdir -p "${HOME}"
  # Confirm the dir does not exist before the call.
  [ ! -d "${HOME}/.config/gh" ]
  _ensure_host_dirs
  [ -d "${HOME}/.config/gh" ]
}

@test "_ensure_host_dirs: succeeds idempotently when ~/.config/gh already exists" {
  export HOME="${BATS_TEST_TMPDIR}/existing-home-$$"
  mkdir -p "${HOME}/.config/gh"
  run _ensure_host_dirs
  [ "$status" -eq 0 ]
}

# ── _append_credential_mount_args ──────────────────────────────────────────────

@test "_append_credential_mount_args: always mounts ~/.claude" {
  _setup_canon; _append_credential_mount_args
  _args_include "-v"
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.claude:"* ]]
}

@test "_append_credential_mount_args: always mounts ~/.claude/.credentials.json read-only" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *".credentials.json:ro"* ]]
}

@test "_append_credential_mount_args: always mounts ~/.claude.json" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.claude.json:"* ]]
}

@test "_append_credential_mount_args: always mounts ~/.gitconfig read-only" {
  _setup_canon; _append_credential_mount_args
  [[ "${DOCKER_RUN_ARGS[*]}" == *"/.gitconfig:"*":ro"* ]]
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

# ── _remove_stale_container ────────────────────────────────────────────────────

@test "_remove_stale_container: calls docker rm -f (mock exits 0)" {
  _init_defaults
  run _remove_stale_container
  [ "$status" -eq 0 ]
}

# ── _exec_docker_run ───────────────────────────────────────────────────────────

@test "_exec_docker_run: execs docker run with DOCKER_RUN_ARGS (mock exits 0)" {
  _setup_canon; _setup_fake_home
  _build_docker_run_args
  run _exec_docker_run
  [ "$status" -eq 0 ]
}
