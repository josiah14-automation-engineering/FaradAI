#!/usr/bin/env bash
set -euo pipefail

docker run -it --rm \
  -v "${HOME}/.claude:/home/$(whoami)/.claude" \
  -v "${HOME}/Development/personal:/home/$(whoami)/Development/personal" \
  -w "/home/$(whoami)/Development/personal" \
  faradai:latest \
  claude
