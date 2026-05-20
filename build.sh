#!/usr/bin/env bash
set -euo pipefail

docker build \
  --network=host \
  --build-arg USERNAME="$(whoami)" \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  --build-arg WORKDIR_PATH="${FARADAI_WORKDIR:-${HOME}/Development/personal}" \
  -t faradai:latest \
  "$(dirname "$0")"
