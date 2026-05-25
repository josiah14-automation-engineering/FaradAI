#!/usr/bin/env bash
set -euo pipefail

if ! command -v sudo > /dev/null 2>&1; then
  echo "install.sh: sudo is required but not available" >&2
  exit 1
fi

if ! command -v docker > /dev/null 2>&1; then
  echo "install.sh: docker is not installed or not in PATH" >&2
  exit 1
fi

if ! docker info > /dev/null 2>&1; then
  echo "install.sh: Docker daemon is not running" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/build.sh"
sudo install -m 755 "${SCRIPT_DIR}/faradai" /usr/local/bin/faradai
sudo install -m 755 "${SCRIPT_DIR}/uninstall-faradai" /usr/local/bin/uninstall-faradai
