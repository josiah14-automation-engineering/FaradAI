#!/usr/bin/env bash
set -euo pipefail

_usage() {
  echo "Usage: faradai [claude|aider|bash]"
  echo "  claude  Launch Claude Code (default)"
  echo "  aider   Launch aider"
  echo "  bash    Open a bash shell"
}

case "${1:-claude}" in
  claude)
    exec claude
    ;;
  aider)
    exec aider
    ;;
  bash)
    exec bash
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
