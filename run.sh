#!/usr/bin/env bash
set -euo pipefail

docker run -it --rm \
  -v "${HOME}/.claude:/home/$(whoami)/.claude" \
  -v "${HOME}/.gitconfig:/home/$(whoami)/.gitconfig:ro" \
  -v "${HOME}/Development/personal:/home/$(whoami)/Development/personal" \
  -w "/home/$(whoami)/Development/personal" \
  -e OPENROUTER_API_KEY="$(pass show openrouter/api-key)" \
  faradai:latest \
  "${@:-claude}"
