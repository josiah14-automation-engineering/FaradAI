#!/usr/bin/env bash
set -euo pipefail

docker build \
  --pull \
  --network=host \
  --build-arg USERNAME="$(whoami)" \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  -t faradai:latest \
  "$(cd "$(dirname "$0")" && pwd)"
