#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/build.sh"
sudo install -m 755 "${SCRIPT_DIR}/faradai" /usr/local/bin/faradai
sudo install -m 755 "${SCRIPT_DIR}/uninstall-faradai" /usr/local/bin/uninstall-faradai
