#!/usr/bin/env bash
###############################################################################
# dev-cli installer
#
# Install:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/dev-cli/main/install.sh | bash
#
# Or from a cloned repo:
#   ./install.sh
#
# What it does:
#   1. Copies bin/dev and bin/dev-hub to ~/.local/bin/
#   2. Adds shell aliases to ~/.bashrc
#   3. Creates config directory structure
#   4. Optionally runs bootstrap.sh for full VPS setup
###############################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}→${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/dev-cli"

echo ""
echo "  Installing dev-cli..."
echo ""

# Ensure directories
mkdir -p "$BIN_DIR" "$CONFIG_DIR"/{templates,hooks,projects,logs,secrets}
mkdir -p "$HOME/images"

# Copy binaries
cp "$REPO_DIR/bin/dev" "$BIN_DIR/dev"
cp "$REPO_DIR/bin/dev-hub" "$BIN_DIR/dev-hub"
chmod +x "$BIN_DIR/dev" "$BIN_DIR/dev-hub"
log "Installed dev and dev-hub to $BIN_DIR/"

# Ensure PATH includes ~/.local/bin
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  for rcfile in ~/.bashrc ~/.zshrc; do
    if [ -f "$rcfile" ] && ! grep -q 'local/bin' "$rcfile"; then
      echo '' >> "$rcfile"
      echo '# dev-cli' >> "$rcfile"
      echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$rcfile"
    fi
  done
  export PATH="$BIN_DIR:$PATH"
  log "Added $BIN_DIR to PATH"
fi

# Add aliases (idempotent)
ALIAS_MARKER="# dev-cli aliases"
for rcfile in ~/.bashrc ~/.zshrc; do
  if [ -f "$rcfile" ] && ! grep -q "$ALIAS_MARKER" "$rcfile"; then
    cat >> "$rcfile" << 'ALIASES'

# dev-cli aliases
alias d="dev"
alias dl="dev ls"
alias da="dev attach"
alias dk="dev kill"
alias dh="dev hub"
alias lg="lazygit"
alias t="tmux"
alias ta="tmux attach"
alias tl="tmux ls"
alias proj="cd ~/projects"
ALIASES
    log "Added aliases to $rcfile"
  fi
done

# Create secrets file if it doesn't exist
if [ ! -f "$CONFIG_DIR/secrets.env" ]; then
  cat > "$CONFIG_DIR/secrets.env" << 'SECRETS'
# API Keys — this file is chmod 600
# Sourced by dev CLI when launching agents

# Claude Code (Anthropic)
# ANTHROPIC_API_KEY=sk-ant-...

# Codex (OpenAI)
# OPENAI_API_KEY=sk-...
SECRETS
  chmod 600 "$CONFIG_DIR/secrets.env"
  log "Created $CONFIG_DIR/secrets.env"
fi

# Create empty port registry if it doesn't exist
if [ ! -f "$CONFIG_DIR/ports.json" ]; then
  echo '{}' > "$CONFIG_DIR/ports.json"
  log "Created port registry"
fi

echo ""
log "dev-cli installed!"
echo ""
echo "  Run 'dev help' to get started."
echo "  Run 'dev init' to set up your first project."
echo ""

# Offer full bootstrap
echo -ne "  Run full VPS bootstrap (installs brew, node, docker, tmux, etc.)? [y/N]: "
read -r do_bootstrap
if [ "$do_bootstrap" = "y" ] || [ "$do_bootstrap" = "Y" ]; then
  bash "$REPO_DIR/bootstrap.sh"
fi
