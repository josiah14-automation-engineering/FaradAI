#!/usr/bin/env bash
set -euo pipefail

USER="$(whoami)"

docker run -it --rm \
  --memory=4g \
  --cpus=4 \
  -v "${HOME}/.claude:/home/${USER}/.claude" \
  -v "${HOME}/.gitconfig:/home/${USER}/.gitconfig:ro" \
  -v "${HOME}/Development/personal:/home/${USER}/Development/personal" \
  -w "/home/${USER}/Development/personal" \
  -e OPENROUTER_API_KEY="$(pass show openrouter/api-key)" \
  faradai:latest \
  "${@:-claude}"
</arg_value>