#!/usr/bin/env bats
#
# Black-box tests for entrypoint.sh: it has no source-vs-execute guard (it
# always dispatches via the trailing case/exec), so — like unit.bats does for
# the faradai CLI — these run it as a real subprocess against call-logging
# mocks (test/helpers/entrypoint/) rather than sourcing it.

ENTRYPOINT="${BATS_TEST_DIRNAME}/../entrypoint.sh"

setup() {
  export PATH="${BATS_TEST_DIRNAME}/helpers/entrypoint:${PATH}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export MOCK_CALL_LOG_DIR="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "${MOCK_CALL_LOG_DIR}"
}

@test "headroom: removes its retired tokensave MCP block from persistent Codex config" {
  mkdir -p "${HOME}/.codex"
  printf '%s\n' 'keep = true' '# --- Headroom MCP server: tokensave ---' '[mcp_servers.tokensave]' 'command = "/home/faradai/.local/bin/tokensave"' 'args = ["serve"]' '# --- end Headroom MCP server: tokensave ---' 'also_keep = true' > "${HOME}/.codex/config.toml"

  run env bash "${ENTRYPOINT}" bash -c true

  [ "$status" -eq 0 ]
  ! grep -q "tokensave" "${HOME}/.codex/config.toml"
  grep -qx "keep = true" "${HOME}/.codex/config.toml"
  grep -qx "also_keep = true" "${HOME}/.codex/config.toml"
}

# ── ponytail provisioning: claude ──────────────────────────────────────────

@test "ponytail: FARADAI_ENABLE_PONYTAIL unset — claude plugin commands not invoked" {
  run env bash "${ENTRYPOINT}" claude --version
  [ "$status" -eq 0 ]
  ! grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/claude.log"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=0 — claude plugin commands not invoked" {
  run env FARADAI_ENABLE_PONYTAIL=0 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  ! grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/claude.log"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — adds the ponytail marketplace to claude" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" claude --version
  [ "$status" -eq 0 ]
  grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/claude.log"
  grep -qF "DietrichGebert/ponytail" "${MOCK_CALL_LOG_DIR}/claude.log"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — installs ponytail@ponytail at user scope on claude" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  grep -qF "ponytail@ponytail" "${MOCK_CALL_LOG_DIR}/claude.log"
  grep -qx -- "--scope" "${MOCK_CALL_LOG_DIR}/claude.log"
  grep -qx "user" "${MOCK_CALL_LOG_DIR}/claude.log"
}

@test "ponytail: claude plugin failure does not abort the launch" {
  run env FARADAI_ENABLE_PONYTAIL=1 MOCK_CLAUDE_PLUGIN_EXIT=1 bash "${ENTRYPOINT}" claude --resume
  [ "$status" -eq 0 ]
  grep -qx -- "--resume" "${MOCK_CALL_LOG_DIR}/claude.log"
}

# ── ponytail provisioning: codex ───────────────────────────────────────────

@test "ponytail: FARADAI_ENABLE_PONYTAIL unset — codex plugin commands not invoked" {
  run env bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALL_LOG_DIR}/codex.log" ]
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — adds the ponytail marketplace to codex" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/codex.log"
  grep -qF "DietrichGebert/ponytail" "${MOCK_CALL_LOG_DIR}/codex.log"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — adds ponytail@ponytail on codex" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  grep -qF "ponytail@ponytail" "${MOCK_CALL_LOG_DIR}/codex.log"
}

@test "ponytail: codex plugin failure does not abort the launch" {
  run env FARADAI_ENABLE_PONYTAIL=1 MOCK_CODEX_PLUGIN_EXIT=1 bash "${ENTRYPOINT}" codex --resume
  [ "$status" -eq 0 ]
  grep -qx -- "--resume" "${MOCK_CALL_LOG_DIR}/codex.log"
}

# ── ponytail provisioning: opencode (config file, not a plugin command) ────

@test "ponytail: FARADAI_ENABLE_PONYTAIL unset — opencode.json not created" {
  run env bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  [ ! -f "${HOME}/.config/opencode/opencode.json" ]
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — creates opencode.json with ponytail plugin when absent" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" opencode
  [ "$status" -eq 0 ]
  [ -f "${HOME}/.config/opencode/opencode.json" ]
  jq -e '.plugin | index("@dietrichgebert/ponytail")' "${HOME}/.config/opencode/opencode.json"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — preserves existing opencode.json keys and other plugins" {
  mkdir -p "${HOME}/.config/opencode"
  printf '{"model":"anthropic/claude","plugin":["other-plugin"]}' > "${HOME}/.config/opencode/opencode.json"
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" opencode
  [ "$status" -eq 0 ]
  [ "$(jq -r '.model' "${HOME}/.config/opencode/opencode.json")" = "anthropic/claude" ]
  jq -e '.plugin | index("other-plugin")' "${HOME}/.config/opencode/opencode.json"
  jq -e '.plugin | index("@dietrichgebert/ponytail")' "${HOME}/.config/opencode/opencode.json"
}

@test "ponytail: FARADAI_ENABLE_PONYTAIL=1 — idempotent, does not duplicate the plugin entry on rerun" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" opencode
  [ "$status" -eq 0 ]
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" opencode
  [ "$status" -eq 0 ]
  local count
  count="$(jq '[.plugin[] | select(. == "@dietrichgebert/ponytail")] | length' "${HOME}/.config/opencode/opencode.json")"
  [ "${count}" -eq 1 ]
}

# ── ponytail provisioning: aider is out of scope, but still triggers the others ─

@test "ponytail: launching aider does not attempt aider plugin commands (no native ponytail support)" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" aider
  [ "$status" -eq 0 ]
  ! grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/aider.log"
}

@test "ponytail: launching aider still provisions claude/codex/opencode (available cross-tool, not per-launch-target)" {
  run env FARADAI_ENABLE_PONYTAIL=1 bash "${ENTRYPOINT}" aider
  [ "$status" -eq 0 ]
  grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/claude.log"
  grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/codex.log"
  [ -f "${HOME}/.config/opencode/opencode.json" ]
}

# ── headroom dispatch ───────────────────────────────────────────────────────

@test "headroom: FARADAI_ENABLE_HEADROOM unset — tool invoked directly, headroom never called" {
  run env bash "${ENTRYPOINT}" claude --resume
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALL_LOG_DIR}/headroom.log" ]
  grep -qx -- "--resume" "${MOCK_CALL_LOG_DIR}/claude.log"
}

@test "headroom: FARADAI_ENABLE_HEADROOM=0 — tool invoked directly" {
  run env FARADAI_ENABLE_HEADROOM=0 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALL_LOG_DIR}/headroom.log" ]
}

@test "headroom: FARADAI_ENABLE_HEADROOM=1 — wraps claude via 'headroom wrap claude -- ARGS'" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" claude --resume
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALL_LOG_DIR}/claude.log" ]
  grep -qx "wrap" "${MOCK_CALL_LOG_DIR}/headroom.log"
  grep -qx "claude" "${MOCK_CALL_LOG_DIR}/headroom.log"
  grep -qx -- "--" "${MOCK_CALL_LOG_DIR}/headroom.log"
  grep -qx -- "--resume" "${MOCK_CALL_LOG_DIR}/headroom.log"
}

@test "headroom: FARADAI_ENABLE_HEADROOM=1 — wraps codex" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" codex
  [ "$status" -eq 0 ]
  grep -qx "codex" "${MOCK_CALL_LOG_DIR}/headroom.log"
}

@test "headroom: FARADAI_ENABLE_HEADROOM=1 — wraps aider (headroom supports it even though ponytail doesn't)" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" aider --no-git
  [ "$status" -eq 0 ]
  grep -qx "aider" "${MOCK_CALL_LOG_DIR}/headroom.log"
  grep -qx -- "--no-git" "${MOCK_CALL_LOG_DIR}/headroom.log"
}

@test "headroom: FARADAI_ENABLE_HEADROOM=1 — wraps opencode" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" opencode
  [ "$status" -eq 0 ]
  grep -qx "opencode" "${MOCK_CALL_LOG_DIR}/headroom.log"
}

@test "headroom: FARADAI_ENABLE_HEADROOM=1 — no args defaults to wrapping claude" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}"
  [ "$status" -eq 0 ]
  grep -qx "claude" "${MOCK_CALL_LOG_DIR}/headroom.log"
}

@test "headroom: bash command bypasses wrapping entirely, even when enabled" {
  run env FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" bash -c "echo hi"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALL_LOG_DIR}/headroom.log" ]
  [[ "$output" == *"hi"* ]]
}

# ── both flags together ─────────────────────────────────────────────────────

@test "both flags: ponytail provisions, then headroom wraps, for the same launch" {
  run env FARADAI_ENABLE_PONYTAIL=1 FARADAI_ENABLE_HEADROOM=1 bash "${ENTRYPOINT}" claude
  [ "$status" -eq 0 ]
  grep -qx "plugin" "${MOCK_CALL_LOG_DIR}/claude.log"
  grep -qx "wrap" "${MOCK_CALL_LOG_DIR}/headroom.log"
  grep -qx "claude" "${MOCK_CALL_LOG_DIR}/headroom.log"
}
