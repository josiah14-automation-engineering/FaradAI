#!/usr/bin/env bash
set -euo pipefail

case "${1:-claude}" in
  claude)
    exec claude
    ;;
  aider)
    exec aider
    ;;
  tmux)
    tmux new-session -d -s faradai
    tmux split-window -h -t faradai
    tmux send-keys -t faradai:0.0 'claude' Enter
    tmux send-keys -t faradai:0.1 'aider' Enter
    exec tmux attach-session -t faradai
    ;;
  bash)
    exec bash
    ;;
  *)
    echo "Usage: run.sh [claude|aider|tmux|bash]" >&2
    echo "  claude  Launch Claude Code (default)" >&2
    echo "  aider   Launch aider" >&2
    echo "  tmux    Launch both in a split tmux session" >&2
    echo "  bash    Drop to a bash shell" >&2
    exit 1
    ;;
esac
