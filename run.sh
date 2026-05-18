#!/usr/bin/env bash
set -euo pipefail

USER="$(whoami)"

docker run -it --rm \
  --memory=4g \
  --cpus=4 \
  -v "${HOME}/.claude:/home/${USER}/.claude" \
  -v "${HOME}/.claude.json:/home/${USER}/.claude.json" \
  -v "${HOME}/.aider.conf.yml:/home/${USER}/.aider.conf.yml:ro" \
  -v "${HOME}/.gitconfig:/home/${USER}/.gitconfig:ro" \
  -v "${HOME}/Development/personal:/home/${USER}/Development/personal" \
  -w "/home/${USER}/Development/personal" \
  faradai:latest \
  "${@:-claude}"
