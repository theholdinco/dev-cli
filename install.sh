#!/usr/bin/env bash
###############################################################################
# dev-cli installer
#
# Install from a cloned repo:
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
mkdir -p "$BIN_DIR" "$CONFIG_DIR"/{templates,hooks,projects,logs,secrets,prompts}
mkdir -p "$HOME/images"

# Install binaries (atomic mv so a running 'dev' process isn't corrupted mid-read)
cp "$REPO_DIR/bin/dev" "$BIN_DIR/dev.new"
cp "$REPO_DIR/bin/dev-hub" "$BIN_DIR/dev-hub.new"
cp "$REPO_DIR/bin/claude-tg-notify" "$BIN_DIR/claude-tg-notify.new"
cp "$REPO_DIR/bin/dev-task-runner" "$BIN_DIR/dev-task-runner.new"
chmod +x "$BIN_DIR/dev.new" "$BIN_DIR/dev-hub.new" "$BIN_DIR/claude-tg-notify.new" "$BIN_DIR/dev-task-runner.new"
mv "$BIN_DIR/dev.new" "$BIN_DIR/dev"
mv "$BIN_DIR/dev-hub.new" "$BIN_DIR/dev-hub"
mv "$BIN_DIR/claude-tg-notify.new" "$BIN_DIR/claude-tg-notify"
mv "$BIN_DIR/dev-task-runner.new" "$BIN_DIR/dev-task-runner"
log "Installed dev, dev-hub, claude-tg-notify, and dev-task-runner to $BIN_DIR/"

# Install web dashboard files
WEB_DIR="$HOME/.local/share/dev-cli/web"
mkdir -p "$WEB_DIR"
if [ -d "$REPO_DIR/web" ]; then
  cp -r "$REPO_DIR/web/"* "$WEB_DIR/"
  log "Installed web dashboard to $WEB_DIR/"
fi

# Install default prompt templates (don't overwrite user customizations)
if [ -d "$REPO_DIR/prompts" ]; then
  for pf in "$REPO_DIR/prompts/"*.md; do
    [ -f "$pf" ] || continue
    _basename=$(basename "$pf")
    if [ ! -f "$CONFIG_DIR/prompts/$_basename" ]; then
      cp "$pf" "$CONFIG_DIR/prompts/$_basename"
      log "Installed default prompt: $_basename"
    fi
  done
fi

# Set up Python venv if python3 available
if command -v python3 &>/dev/null; then
  VENV_DIR="$CONFIG_DIR/venv"
  if [ ! -d "$VENV_DIR" ]; then
    info "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR" 2>/dev/null || warn "Failed to create Python venv (optional)"
  fi
  if [ -d "$VENV_DIR" ] && [ -f "$WEB_DIR/requirements.txt" ]; then
    info "Installing Python dependencies..."
    "$VENV_DIR/bin/pip" install -q -r "$WEB_DIR/requirements.txt" 2>/dev/null || warn "Failed to install Python deps (optional)"
  fi
else
  info "python3 not found — web dashboard and bot features will be unavailable"
fi

# Check recommended dependencies
info "Checking dependencies..."
_missing=0
for _tool in lazygit:https://github.com/jesseduffield/lazygit \
             delta:https://github.com/dandavison/delta \
             docker:https://docs.docker.com/get-docker/ \
             tailscale:https://tailscale.com/download; do
  _name="${_tool%%:*}"
  _url="${_tool#*:}"
  if ! command -v "$_name" &>/dev/null; then
    warn "$_name not found — install: $_url"
    _missing=$((_missing + 1))
  fi
done
if [ "$_missing" -gt 0 ]; then
  info "Run ./bootstrap.sh for automatic installation of missing tools"
else
  log "All dependencies found"
fi

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

# Migrate local port registry to global if available
GLOBAL_PORT_REGISTRY="/etc/dev-cli/ports.json"
if [ -f "$GLOBAL_PORT_REGISTRY" ] && [ -w "$GLOBAL_PORT_REGISTRY" ]; then
  LOCAL_PORTS="$CONFIG_DIR/ports.json"
  if [ -f "$LOCAL_PORTS" ] && [ "$(jq 'length' "$LOCAL_PORTS" 2>/dev/null)" -gt 0 ]; then
    info "Migrating local port registry to global..."
    local_tmp=$(mktemp)
    (
      flock -x 200
      jq -s '.[0] * .[1]' "$GLOBAL_PORT_REGISTRY" "$LOCAL_PORTS" > "$local_tmp"
      mv "$local_tmp" "$GLOBAL_PORT_REGISTRY"
    ) 200>"${GLOBAL_PORT_REGISTRY}.lock"
    mv "$LOCAL_PORTS" "${LOCAL_PORTS}.migrated"
    log "Migrated local sessions to global registry (local backed up as ports.json.migrated)"
  fi
elif [ ! -f "$CONFIG_DIR/ports.json" ]; then
  echo '{}' > "$CONFIG_DIR/ports.json"
  log "Created local port registry"
fi

# Create empty task registry if it doesn't exist
if [ ! -f "$CONFIG_DIR/tasks.json" ]; then
  echo '{"tasks":[],"next_id":1}' > "$CONFIG_DIR/tasks.json"
  log "Created task registry"
fi

# Install tab completion
info "Setting up tab completion..."
COMPLETION_FILE="$CONFIG_DIR/completion.bash"
cp "$REPO_DIR/completions/dev.bash" "$COMPLETION_FILE"
log "Installed tab completion at $COMPLETION_FILE"

# Source completion from shell rc files (idempotent)
COMPLETION_MARKER="# dev-cli completion"
for rcfile in ~/.bashrc ~/.zshrc; do
  if [ -f "$rcfile" ] && ! grep -q "$COMPLETION_MARKER" "$rcfile"; then
    cat >> "$rcfile" << COMP_SOURCE

$COMPLETION_MARKER
[ -f "$CONFIG_DIR/completion.bash" ] && source "$CONFIG_DIR/completion.bash"
COMP_SOURCE
    log "Added completion source to $rcfile"
  fi
done

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
