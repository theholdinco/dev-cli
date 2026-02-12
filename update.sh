#!/usr/bin/env bash
# Update dev-cli from the repo
# Usage: dev update (or run this script directly)

set -euo pipefail

REPO_DIR="$HOME/.dev-cli-repo"

if [ ! -d "$REPO_DIR" ]; then
  echo "Error: Repo not found at $REPO_DIR"
  echo "Re-clone and run install.sh instead."
  exit 1
fi

cd "$REPO_DIR"
git pull origin main
./install.sh

echo "✓ Updated to latest version"
