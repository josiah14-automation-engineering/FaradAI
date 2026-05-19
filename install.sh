#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "${SCRIPT_DIR}/faradai"
sudo install -m 755 "${SCRIPT_DIR}/faradai" /usr/local/bin/faradai
