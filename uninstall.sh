#!/usr/bin/env bash
# Uninstall dev-cli (keeps config and projects)

set -euo pipefail

rm -f ~/.local/bin/dev ~/.local/bin/dev-hub
echo "Removed binaries. Config at ~/.config/dev-cli/ and projects preserved."
echo "Remove them manually if needed."
