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
mkdir -p "$BIN_DIR" "$CONFIG_DIR"/{templates,hooks,projects,logs,secrets}
mkdir -p "$HOME/images"

# Install binaries (atomic mv so a running 'dev' process isn't corrupted mid-read)
cp "$REPO_DIR/bin/dev" "$BIN_DIR/dev.new"
cp "$REPO_DIR/bin/dev-hub" "$BIN_DIR/dev-hub.new"
chmod +x "$BIN_DIR/dev.new" "$BIN_DIR/dev-hub.new"
mv "$BIN_DIR/dev.new" "$BIN_DIR/dev"
mv "$BIN_DIR/dev-hub.new" "$BIN_DIR/dev-hub"
log "Installed dev and dev-hub to $BIN_DIR/"

# Install web dashboard files
WEB_DIR="$HOME/.local/share/dev-cli/web"
mkdir -p "$WEB_DIR"
if [ -d "$REPO_DIR/web" ]; then
  cp -r "$REPO_DIR/web/"* "$WEB_DIR/"
  log "Installed web dashboard to $WEB_DIR/"
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

# Create empty port registry if it doesn't exist
if [ ! -f "$CONFIG_DIR/ports.json" ]; then
  echo '{}' > "$CONFIG_DIR/ports.json"
  log "Created port registry"
fi

# Generate tab completion
info "Setting up tab completion..."
COMPLETION_FILE="$CONFIG_DIR/completion.bash"
cat > "$COMPLETION_FILE" << 'COMPLETION'
# dev-cli tab completion
_dev() {
  local cur prev commands session_cmds project_cmds
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # All available commands
  commands="init setup new ls attach kill hub dashboard ports logs url supabase pr shell worktree img projects update help status restart send diff sync gc template config agent stats doctor web bot services mobile m"

  # Commands that take a session name as argument
  session_cmds="attach kill logs url shell pr status restart send diff sync"

  # Commands that take a project name as argument
  project_cmds="new setup template worktree"

  # First argument: complete command names
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    return 0
  fi

  # Second argument: depends on the command
  local cmd="${COMP_WORDS[1]}"

  # Session name completion
  if echo " $session_cmds " | grep -q " $cmd "; then
    local sessions
    sessions=$(jq -r 'keys[]' "$HOME/.config/dev-cli/ports.json" 2>/dev/null)
    if [ -n "$sessions" ]; then
      COMPREPLY=( $(compgen -W "$sessions" -- "$cur") )
    fi
    return 0
  fi

  # Project name completion
  if echo " $project_cmds " | grep -q " $cmd "; then
    local projects=""
    if [ -d "$HOME/.config/dev-cli/projects" ]; then
      projects=$(ls "$HOME/.config/dev-cli/projects/" 2>/dev/null | sed 's/\.json$//')
    fi
    if [ -n "$projects" ]; then
      COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
    fi
    return 0
  fi

  # Supabase subcommands
  if [ "$cmd" = "supabase" ] && [ "$COMP_CWORD" -eq 3 ]; then
    COMPREPLY=( $(compgen -W "start stop reset status" -- "$cur") )
    return 0
  fi

  # img subcommands
  if [ "$cmd" = "img" ] && [ "$COMP_CWORD" -eq 2 ]; then
    COMPREPLY=( $(compgen -W "ls cp grab path clean" -- "$cur") )
    return 0
  fi

  # web subcommands
  if [ "$cmd" = "web" ] && [ "$COMP_CWORD" -eq 2 ]; then
    COMPREPLY=( $(compgen -W "setup start stop status" -- "$cur") )
    return 0
  fi

  # bot subcommands
  if [ "$cmd" = "bot" ] && [ "$COMP_CWORD" -eq 2 ]; then
    COMPREPLY=( $(compgen -W "setup start stop status" -- "$cur") )
    return 0
  fi

  # services subcommands
  if [ "$cmd" = "services" ] && [ "$COMP_CWORD" -eq 2 ]; then
    COMPREPLY=( $(compgen -W "install uninstall start stop restart status logs" -- "$cur") )
    return 0
  fi

  # kill flags
  if [ "$cmd" = "kill" ]; then
    COMPREPLY=( $(compgen -W "--all --project" -- "$cur") )
    return 0
  fi

  return 0
}

complete -F _dev dev
COMPLETION
log "Generated tab completion at $COMPLETION_FILE"

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
