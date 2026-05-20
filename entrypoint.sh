#!/usr/bin/env bash
set -euo pipefail

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
  *)
    echo "Usage: faradai [claude|aider|bash]" >&2
    echo "  claude     Launch Claude Code (default)" >&2
    echo "  aider      Launch aider" >&2
    echo "  bash       Open a bash shell" >&2
    echo "  uninstall  Remove faradai (run from outside the container)" >&2
    exit 1
    ;;
esac
