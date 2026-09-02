#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

docker build \
  --pull \
  --network=host \
  --file "${SCRIPT_DIR}/Containerfile" \
  --build-arg USERNAME="$(id -un)" \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  -t faradai:latest \
  "${SCRIPT_DIR}"
