#!/usr/bin/env bash
set -euo pipefail

USER="$(whoami)"
FARADAI_MEMORY="${FARADAI_MEMORY:-4g}"
FARADAI_CPUS="${FARADAI_CPUS:-4}"
FARADAI_PIDS="${FARADAI_PIDS:-512}"

TMUX_CONF_MOUNT=()
if [ -f "${HOME}/.tmux.conf" ]; then
  TMUX_CONF_MOUNT=(-v "${HOME}/.tmux.conf:/home/${USER}/.tmux.conf:ro")
fi

TMUX_PLUGINS_MOUNT=()
if [ -d "${HOME}/.tmux/plugins" ]; then
  TMUX_PLUGINS_MOUNT=(-v "${HOME}/.tmux/plugins:/home/${USER}/.tmux/plugins")
fi

docker run -it --rm \
  --memory="${FARADAI_MEMORY}" \
  --cpus="${FARADAI_CPUS}" \
  --pids-limit="${FARADAI_PIDS}" \
  -v "${HOME}/.claude:/home/${USER}/.claude" \
  -v "${HOME}/.claude/.credentials.json:/home/${USER}/.claude/.credentials.json:ro" \
  -v "${HOME}/.claude.json:/home/${USER}/.claude.json" \
  -v "${HOME}/.aider.conf.yml:/home/${USER}/.aider.conf.yml:ro" \
  -v "${HOME}/.gitconfig:/home/${USER}/.gitconfig:ro" \
  -v "${HOME}/.ssh:/home/${USER}/.ssh:ro" \
  -v "${HOME}/Development/personal:/home/${USER}/Development/personal" \
  "${TMUX_CONF_MOUNT[@]}" \
  "${TMUX_PLUGINS_MOUNT[@]}" \
  -w "/home/${USER}/Development/personal" \
  faradai:latest \
  "$@"
