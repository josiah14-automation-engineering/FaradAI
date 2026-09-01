#!/usr/bin/env bash
set -euo pipefail

_usage() {
  cat <<'EOF'
Usage: faradai [COMMAND [ARGS...]]

Commands (container-internal):
  (none)     Launch Claude Code (default)
  claude     Launch Claude Code; remaining args passed through
  codex      Launch Codex; remaining args passed through
  aider      Launch aider; remaining args passed through
  opencode   Launch OpenCode; remaining args passed through
  bash       Open a bash shell

Host-side commands (logs, status, version, update, uninstall) must be
run via the faradai CLI on the host, not through the container entrypoint.
EOF
}

_PONYTAIL_MARKETPLACE="DietrichGebert/ponytail"
_PONYTAIL_OPENCODE_PACKAGE="@dietrichgebert/ponytail"

# Headroom 0.37 retired tokensave, but its ownership ledger lives in the
# replaced container while Codex's config persists on the host mount.
_cleanup_retired_tokensave() {
  local cfg="${HOME}/.codex/config.toml"
  [[ -f "${cfg}" ]] || return 0
  sed -i '/^# --- Headroom MCP server: tokensave ---$/,/^# --- end Headroom MCP server: tokensave ---$/d' "${cfg}"
}

# _provision_ponytail_claude / _codex / _opencode
#
# Each is a no-op if its tool isn't installed. claude/codex have their own
# plugin-manager commands, which we trust to be idempotent (re-running
# marketplace add / install against an already-installed plugin is their
# problem to no-op or fast-update, not ours to track separately). OpenCode
# has no install command — it just reads a config file — so that one gets
# real merge logic: preserve whatever else is already in opencode.json,
# add the plugin package only if it isn't already listed.
#
# `A && B || echo warning` is the standard set -e-safe way to attempt a
# multi-step operation without aborting the script on failure: bash only
# treats the last command in an &&/|| chain as significant for set -e, so a
# failed marketplace-add or plugin-install here logs a warning and lets the
# container boot into the actual tool anyway.
_provision_ponytail_claude() {
  command -v claude > /dev/null 2>&1 || return 0
  claude plugin marketplace add "${_PONYTAIL_MARKETPLACE}" \
    && claude plugin install ponytail@ponytail --scope user \
    || echo "entrypoint: warning: ponytail provisioning failed for claude" >&2
}

_provision_ponytail_codex() {
  command -v codex > /dev/null 2>&1 || return 0
  codex plugin marketplace add "${_PONYTAIL_MARKETPLACE}" \
    && codex plugin add ponytail@ponytail \
    || echo "entrypoint: warning: ponytail provisioning failed for codex" >&2
}

_provision_ponytail_opencode() {
  command -v opencode > /dev/null 2>&1 || return 0
  command -v jq > /dev/null 2>&1 \
    || { echo "entrypoint: warning: jq not found — skipping ponytail provisioning for opencode" >&2; return 0; }

  local cfg="${HOME}/.config/opencode/opencode.json"
  mkdir -p "${HOME}/.config/opencode"

  if [[ ! -f "${cfg}" ]]; then
    # $schema is literal JSON text, not a shell variable — single-quoted on purpose.
    # shellcheck disable=SC2016
    printf '{"$schema":"https://opencode.ai/config.json","plugin":["%s"]}\n' \
      "${_PONYTAIL_OPENCODE_PACKAGE}" > "${cfg}"
    return 0
  fi

  if jq -e --arg pkg "${_PONYTAIL_OPENCODE_PACKAGE}" \
      '(.plugin // []) | index($pkg) != null' "${cfg}" > /dev/null 2>&1; then
    return 0
  fi

  local tmp
  tmp="$(mktemp "${cfg}.XXXXXX")"
  if jq --arg pkg "${_PONYTAIL_OPENCODE_PACKAGE}" \
      '.plugin = ((.plugin // []) + [$pkg])' "${cfg}" > "${tmp}"; then
    mv "${tmp}" "${cfg}"
  else
    rm -f "${tmp}"
    echo "entrypoint: warning: failed to update ${cfg} for ponytail" >&2
  fi
}

# _provision_ponytail
#
# Gated on FARADAI_ENABLE_PONYTAIL (set by the faradai CLI via
# _append_feature_flag_args, which already folds in the
# FARADAI_NETWORK_MODE=none override — this function trusts the value it
# receives rather than re-deriving that decision).
#
# Always attempts all three targets regardless of which tool is being
# launched this call, not just the one named on the command line: a single
# container's lifetime can span multiple tools (`faradai claude` today,
# `faradai codex` attaching to the same container tomorrow), and there's no
# cross-launch state tracking here (see the idempotency note above) — so
# every launch just re-asserts "ponytail should be available everywhere it
# can be." aider has no ponytail integration upstream, so it's intentionally
# not in this list.
_provision_ponytail() {
  [[ "${FARADAI_ENABLE_PONYTAIL:-0}" == "1" ]] || return 0
  _provision_ponytail_claude
  _provision_ponytail_codex
  _provision_ponytail_opencode
}

# _dispatch_tool TOOL [ARGS...]
#
# Gated on FARADAI_ENABLE_HEADROOM (same trust-the-resolved-value contract
# as ponytail above). `headroom wrap TOOL -- ARGS` is headroom's own launch
# wrapper — it starts the compression proxy and execs TOOL through it.
_dispatch_tool() {
  local tool="$1"
  shift
  if [[ "${FARADAI_ENABLE_HEADROOM:-0}" == "1" ]]; then
    exec headroom wrap "${tool}" -- "$@"
  fi
  exec "${tool}" "$@"
}

_cleanup_retired_tokensave

case "${1:-claude}" in
  claude|codex|aider|opencode)
    _provision_ponytail
    _dispatch_tool "${1:-claude}" "${@:2}"
    ;;
  bash)
    exec bash "${@:2}"
    ;;
  --help|-h|help)
    _usage
    exit 0
    ;;
  *)
    echo "faradai: unknown command '$1'" >&2
    _usage >&2
    exit 1
    ;;
esac
