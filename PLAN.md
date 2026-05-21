# faradai script refactor plan

## Goal
Extract validation into functions, fix if-block hygiene, fix update fall-through.
No behaviour changes — pure structural cleanup.

---

## Functions to extract

### `_validate_memory`
Wraps lines 61–79. Takes no args; reads `FARADAI_MEMORY` from env.
Sets `_mem_unit` (lowercased) as a side effect for use in docker run? No —
`docker run --memory` accepts the original value directly. No side effects needed.
Just validate and exit 1 on failure.

```bash
_validate_memory() {
  # k intentionally omitted
  [[ "${FARADAI_MEMORY}" =~ ^([0-9]+(\.[0-9]+)?)([mgMG])$ ]] || {
    echo "faradai: invalid FARADAI_MEMORY '${FARADAI_MEMORY}' (expected e.g. 4g or 512m)" >&2
    exit 1
  }
  local num="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[3],,}" int="${BASH_REMATCH[1]%%.*}"
  if (( int == 0 )) && { [[ "${num}" != *.* ]] || [[ "${num#*.}" =~ ^0+$ ]]; }; then
    echo "faradai: FARADAI_MEMORY must be greater than zero" >&2; exit 1
  fi
  if { [[ "${unit}" == "g" ]] && (( int > 512 )); } ||
     { [[ "${unit}" == "m" ]] && (( int > 524288 )); }; then
    echo "faradai: FARADAI_MEMORY '${FARADAI_MEMORY}' exceeds the 512g sanity limit" >&2; exit 1
  fi
}
```

### `_validate_cpus`
Wraps lines 82–85. Single if, already short — extract for consistency.

```bash
_validate_cpus() {
  [[ "${FARADAI_CPUS}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( ${FARADAI_CPUS%.*} <= 128 )) || {
    echo "faradai: invalid FARADAI_CPUS '${FARADAI_CPUS}' (expected a number <= 128, e.g. 4 or 2.5)" >&2
    exit 1
  }
}
```

### `_validate_pids`
Wraps lines 87–90. Same pattern.

```bash
_validate_pids() {
  [[ "${FARADAI_PIDS}" =~ ^[0-9]+$ ]] || {
    echo "faradai: invalid FARADAI_PIDS '${FARADAI_PIDS}' (expected a positive integer)" >&2
    exit 1
  }
}
```

### `_build_extra_docker_args`
Wraps lines 113–131. Populates EXTRA_DOCKER_ARGS array (declared before call).

```bash
_build_extra_docker_args() {
  [[ -z "${FARADAI_DOCKER_ARGS:-}" ]] && return
  # Word-split only — paths with spaces not supported.
  read -ra EXTRA_DOCKER_ARGS <<< "${FARADAI_DOCKER_ARGS}"
  local permitted=(--env -e --label -l --device --publish -p --hostname)
  local arg flag ok
  for arg in "${EXTRA_DOCKER_ARGS[@]}"; do
    [[ "${arg}" != -* ]] && continue
    ok=0
    for flag in "${permitted[@]}"; do
      [[ "${arg}" == "${flag}" || "${arg}" == "${flag}="* ]] && { ok=1; break; }
    done
    (( ok )) || {
      echo "faradai: FARADAI_DOCKER_ARGS flag '${arg}' is not in the allowlist" >&2
      echo "faradai: permitted: --env/-e, --label/-l, --device, --publish/-p, --hostname" >&2
      exit 1
    }
  done
}
```

---

## Bug fix: update fall-through (#41 partial)

Current `update)` case hits `;;` then falls past `esac` into the docker logic,
starting a container as a side effect of updating. Fix: add `exit 0` after
`install.sh` call (within the case, before `;;`), or restructure as:

```bash
  update)
    _update_dir="$(mktemp -d /tmp/faradai-update-XXXXXX)"
    trap 'rm -rf "${_update_dir}"' EXIT
    git clone git@github.com:josiah14-automation-engineering/faradai.git "${_update_dir}"
    "${_update_dir}/install.sh"
    exit 0
    ;;
```

Note: full #41 fix (SSH→HTTPS) is a separate TODO item. Just fix the fall-through here.

---

## Final script structure after refactor

```
#!/usr/bin/env bash
set -euo pipefail

# ── functions ──────────────────────────────────────────────────────────────────
_usage()                  { ... }
_validate_memory()        { ... }
_validate_cpus()          { ... }
_validate_pids()          { ... }
_build_extra_docker_args(){ ... }

# ── subcommand dispatch ────────────────────────────────────────────────────────
case "${1:-}" in
  --help|-h|help) _usage; exit 0 ;;
  update)   ... exit 0 ;;
  uninstall) exec /usr/local/bin/uninstall-faradai ;;
esac

# ── docker pre-flight ──────────────────────────────────────────────────────────
command -v docker ...

# ── attach if already running ─────────────────────────────────────────────────
[[ running ]] && exec docker exec ...

# ── start fresh: cleanup + trap ───────────────────────────────────────────────
docker rm -f ...
trap ...

# ── config defaults + validation ──────────────────────────────────────────────
FARADAI_WORKDIR=...
FARADAI_MEMORY=...  FARADAI_CPUS=...  FARADAI_PIDS=...
_validate_memory; _validate_cpus; _validate_pids

# ── build optional mount arrays ───────────────────────────────────────────────
USER="$(whoami)"
AIDER_CONF_MOUNT=()   ...
SSH_AGENT_ARGS=()     ...
SSH_DIR_ARGS=()       ...
EXTRA_DOCKER_ARGS=(); _build_extra_docker_args

# ── debug ─────────────────────────────────────────────────────────────────────
[[ debug ]] && set -x ...

# ── run ───────────────────────────────────────────────────────────────────────
exec docker run ...
```

---

## What is NOT changing
- All validation logic and error messages (behaviour-identical)
- Mount table and docker run flags
- FARADAI_DOCKER_ARGS allowlist contents
- entrypoint.sh (already clean)
