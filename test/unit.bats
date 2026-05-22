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
}

# ── flag parser ────────────────────────────────────────────────────────────────

@test "flag parser: -n and -a are mutually exclusive (n then a)" {
  run "${FARADAI}" -n foo -a
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "flag parser: -n and -a are mutually exclusive (a then n)" {
  run "${FARADAI}" -a -n foo
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "flag parser: -n requires a NAME argument" {
  run "${FARADAI}" -n
  [ "$status" -eq 1 ]
  [[ "$output" == *"-n requires a NAME"* ]]
}

@test "flag parser: -a does not consume a known command as NAME" {
  # With docker mocked, -a should try to attach to 'faradai' (not 'faradai-claude').
  # The mock docker inspect returns 'false' (not running), so -a errors with
  # 'no running container faradai' rather than 'faradai-claude'.
  run "${FARADAI}" -a claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai'"* ]]
}

@test "flag parser: -a consumes an unknown word as NAME" {
  run "${FARADAI}" -a myproject
  [ "$status" -eq 1 ]
  [[ "$output" == *"no running container 'faradai-myproject'"* ]]
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

# ── _build_extra_docker_args ───────────────────────────────────────────────────

@test "_build_extra_docker_args: permits --env" {
  run env FARADAI_DOCKER_ARGS="--env FOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: permits -e" {
  run env FARADAI_DOCKER_ARGS="-e FOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: permits --label" {
  run env FARADAI_DOCKER_ARGS="--label app=test" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: permits --hostname" {
  run env FARADAI_DOCKER_ARGS="--hostname myhost" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: denies --volume" {
  run env FARADAI_DOCKER_ARGS="--volume /foo:/bar" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_build_extra_docker_args: denies --network" {
  run env FARADAI_DOCKER_ARGS="--network host" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_build_extra_docker_args: denies --device without opt-in" {
  run env FARADAI_DOCKER_ARGS="--device /dev/snd" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_build_extra_docker_args: permits --device with FARADAI_ALLOW_DEVICE=1" {
  run env FARADAI_DOCKER_ARGS="--device /dev/snd" FARADAI_ALLOW_DEVICE=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: denies --publish without opt-in" {
  run env FARADAI_DOCKER_ARGS="--publish 8080:80" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

@test "_build_extra_docker_args: permits --publish with FARADAI_ALLOW_PUBLISH=1" {
  run env FARADAI_DOCKER_ARGS="--publish 8080:80" FARADAI_ALLOW_PUBLISH=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: permits -p with FARADAI_ALLOW_PUBLISH=1" {
  run env FARADAI_DOCKER_ARGS="-p 8080:80" FARADAI_ALLOW_PUBLISH=1 "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: permits combined short-flag form -eFOO=bar" {
  run env FARADAI_DOCKER_ARGS="-eFOO=bar" "${FARADAI}"
  [ "$status" -eq 0 ]
}

@test "_build_extra_docker_args: denies combined unknown short flag -xFOO" {
  run env FARADAI_DOCKER_ARGS="-xFOO" "${FARADAI}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not permitted"* ]]
}

# ── update subcommand ──────────────────────────────────────────────────────────

@test "update: --branch without NAME exits with error" {
  run "${FARADAI}" update --branch
  [ "$status" -eq 1 ]
  [[ "$output" == *"--branch requires a name"* ]]
}
