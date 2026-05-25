#!/usr/bin/env bash
set -euo pipefail

_usage() {
  cat <<'EOF'
Usage: faradai [COMMAND [ARGS...]]

Commands (container-internal):
  (none)   Launch Claude Code (default)
  claude   Launch Claude Code; remaining args passed through
  aider    Launch aider; remaining args passed through
  bash     Open a bash shell

Host-side commands (logs, status, version, update, uninstall) must be
run via the faradai CLI on the host, not through the container entrypoint.
EOF
}

case "${1:-claude}" in
  claude)
    exec claude "${@:2}"
    ;;
  aider)
    exec aider "${@:2}"
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
