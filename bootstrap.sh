#!/usr/bin/env bash
###############################################################################
# VPS Bootstrap Script
# Run on a blank Hetzner Ubuntu VPS with only gh CLI and Claude Code installed.
#
# Usage:
#   curl -fsSL <raw-gist-url> | bash
#   # OR
#   chmod +x bootstrap.sh && ./bootstrap.sh
#
# What this installs:
#   - System essentials (build-essential, curl, git, unzip, jq, etc.)
#   - Homebrew (linuxbrew)
#   - nvm + Node.js LTS
#   - Docker + Docker Compose
#   - Tailscale
#   - tmux + config
#   - Supabase CLI
#   - lazygit (terminal git UI)
#   - delta (better git diffs)
#   - Codex CLI (OpenAI)
#   - The `dev` CLI (multi-agent manager)
#   - Directory structure
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo "============================================"
echo "  Multi-Agent Dev Environment Bootstrap"
echo "============================================"
echo ""

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

info "Installing system essentials..."
sudo apt install -y \
  build-essential \
  curl \
  wget \
  git \
  unzip \
  zip \
  jq \
  htop \
  tree \
  ripgrep \
  fd-find \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  python3 \
  python3-pip \
  pkg-config \
  libssl-dev \
  file \
  procps

log "System packages installed"

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
if command -v brew &>/dev/null; then
  log "Homebrew already installed"
else
  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add to shell profile
  BREW_PREFIX="/home/linuxbrew/.linuxbrew"
  if [ -d "$BREW_PREFIX" ]; then
    echo '' >> ~/.bashrc
    echo '# Homebrew' >> ~/.bashrc
    echo "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" >> ~/.bashrc
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
  fi

  log "Homebrew installed"
fi

# Make sure brew is in PATH for the rest of the script
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. nvm + Node.js
# ---------------------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"

if [ -d "$NVM_DIR" ]; then
  log "nvm already installed"
else
  info "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  log "nvm installed"
fi

# Source nvm for this script
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if command -v node &>/dev/null; then
  log "Node.js already installed: $(node --version)"
else
  info "Installing Node.js LTS..."
  nvm install --lts
  nvm alias default node
  log "Node.js $(node --version) installed"
fi

# Install global npm packages
info "Installing global npm packages..."
npm install -g pnpm yarn typescript ts-node
log "Global npm packages installed"

# ---------------------------------------------------------------------------
# 4. Docker
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
  log "Docker already installed"
else
  info "Installing Docker..."

  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Allow running docker without sudo
  sudo usermod -aG docker "$USER"

  log "Docker installed (you may need to log out and back in for group changes)"
fi

# ---------------------------------------------------------------------------
# 5. Tailscale
# ---------------------------------------------------------------------------
if command -v tailscale &>/dev/null; then
  log "Tailscale already installed"
else
  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  log "Tailscale installed"
  warn "Run 'sudo tailscale up --ssh' to connect to your Tailscale network"
fi

# ---------------------------------------------------------------------------
# 6. tmux
# ---------------------------------------------------------------------------
if command -v tmux &>/dev/null; then
  log "tmux already installed"
else
  info "Installing tmux..."
  sudo apt install -y tmux
  log "tmux installed"
fi

info "Writing tmux config..."
cat > ~/.tmux.conf << 'TMUXCONF'
# ── Prefix ──────────────────────────────────────────────────
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# ── General ─────────────────────────────────────────────────
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g history-limit 50000
set -g renumber-windows on
set -sg escape-time 10
set -g allow-rename off
set -g focus-events on

# ── Colors ──────────────────────────────────────────────────
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# ── Splits ──────────────────────────────────────────────────
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# ── Navigation ──────────────────────────────────────────────
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D
bind -n M-1 select-window -t 1
bind -n M-2 select-window -t 2
bind -n M-3 select-window -t 3
bind -n M-4 select-window -t 4
bind -n M-5 select-window -t 5

# ── Status Bar ──────────────────────────────────────────────
set -g status-position bottom
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
set -g status-left '#[fg=#89b4fa,bold] #S '
set -g status-left-length 40
set -g status-right '#[fg=#a6adc8] %b %d %H:%M '
set -g window-status-current-format '#[fg=#a6e3a1,bold] #I:#W '
set -g window-status-format '#[fg=#6c7086] #I:#W '
set -g message-style 'bg=#313244 fg=#cdd6f4'

# ── Reload ──────────────────────────────────────────────────
bind r source-file ~/.tmux.conf \; display "Config reloaded!"
TMUXCONF
log "tmux configured"

# ---------------------------------------------------------------------------
# 7. Supabase CLI
# ---------------------------------------------------------------------------
if command -v supabase &>/dev/null; then
  log "Supabase CLI already installed"
else
  info "Installing Supabase CLI..."
  brew install supabase/tap/supabase
  log "Supabase CLI installed"
fi

# ---------------------------------------------------------------------------
# 8. lazygit
# ---------------------------------------------------------------------------
if command -v lazygit &>/dev/null; then
  log "lazygit already installed"
else
  info "Installing lazygit..."
  brew install lazygit
  log "lazygit installed"
fi

# ---------------------------------------------------------------------------
# 9. delta (git pager)
# ---------------------------------------------------------------------------
if command -v delta &>/dev/null; then
  log "delta already installed"
else
  info "Installing delta..."
  brew install git-delta
  log "delta installed"
fi

# Configure git to use delta
info "Configuring git with delta..."
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.dark true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved default
log "Git configured with delta"

# ---------------------------------------------------------------------------
# 10. Codex CLI (OpenAI)
# ---------------------------------------------------------------------------
if command -v codex &>/dev/null; then
  log "Codex CLI already installed"
else
  info "Installing Codex CLI..."
  npm install -g @openai/codex
  log "Codex CLI installed"
fi

# ---------------------------------------------------------------------------
# 11. Directory structure
# ---------------------------------------------------------------------------
info "Creating directory structure..."
mkdir -p ~/projects
mkdir -p ~/.local/bin
mkdir -p ~/.config/dev-cli

# Make sure ~/.local/bin is in PATH
if ! grep -q 'local/bin' ~/.bashrc; then
  echo '' >> ~/.bashrc
  echo '# Local binaries' >> ~/.bashrc
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

log "Directory structure created"

# ---------------------------------------------------------------------------
# 12. Install the `dev` CLI
# ---------------------------------------------------------------------------
info "Installing dev CLI..."
if [ -f "$(dirname "$0")/dev-cli.sh" ]; then
  cp "$(dirname "$0")/dev-cli.sh" ~/.local/bin/dev
else
  warn "dev-cli.sh not found alongside bootstrap.sh"
  warn "Copy dev-cli.sh to ~/.local/bin/dev manually"
fi
chmod +x ~/.local/bin/dev 2>/dev/null || true
log "dev CLI installed"

# ---------------------------------------------------------------------------
# 13. Shell enhancements
# ---------------------------------------------------------------------------
info "Adding shell aliases and helpers..."
cat >> ~/.bashrc << 'BASHRC'

# ── Dev CLI shortcuts ───────────────────────────────────────
alias d="dev"
alias dl="dev ls"
alias da="dev attach"
alias dk="dev kill"
alias dd="dev dashboard"

# ── General aliases ─────────────────────────────────────────
alias lg="lazygit"
alias t="tmux"
alias ta="tmux attach"
alias tl="tmux ls"

# ── Quick navigation ────────────────────────────────────────
alias proj="cd ~/projects"
BASHRC
log "Shell enhancements added"

# ---------------------------------------------------------------------------
# 14. API keys placeholder
# ---------------------------------------------------------------------------
if [ ! -f ~/.config/dev-cli/secrets.env ]; then
  info "Creating API keys placeholder..."
  cat > ~/.config/dev-cli/secrets.env << 'SECRETS'
# API Keys — chmod 600 this file
# These are sourced by the dev CLI when launching agents

# Claude Code (Anthropic)
# ANTHROPIC_API_KEY=sk-ant-...

# Codex (OpenAI)
# OPENAI_API_KEY=sk-...
SECRETS
  chmod 600 ~/.config/dev-cli/secrets.env
  log "API keys file created at ~/.config/dev-cli/secrets.env"
  warn "Edit ~/.config/dev-cli/secrets.env with your API keys"
fi

# ---------------------------------------------------------------------------
# 15. Multi-user helper (add-dev-user)
# ---------------------------------------------------------------------------
info "Installing add-dev-user helper..."
sudo tee /usr/local/bin/add-dev-user > /dev/null << 'ADD_USER_SCRIPT'
#!/usr/bin/env bash
###############################################################################
# add-dev-user — Add a new engineer to the shared dev VPS
#
# Usage: sudo add-dev-user <username>
#
# Creates a Linux user, adds to docker group, installs dev-cli,
# and links shared project secrets.
###############################################################################

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Must run as root (sudo add-dev-user <username>)"
  exit 1
fi

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  echo "Usage: sudo add-dev-user <username>"
  exit 1
fi

echo "Creating user: $USERNAME"

# Create user with home directory
if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists, skipping creation"
else
  useradd -m -s /bin/bash "$USERNAME"
  echo "  ✓ User created"
fi

# Add to docker group
usermod -aG docker "$USERNAME" 2>/dev/null || true
echo "  ✓ Added to docker group"

# Install dev-cli for the user
DEV_CLI_REPO="/opt/dev-cli"
if [ -d "$DEV_CLI_REPO" ]; then
  su - "$USERNAME" -c "bash $DEV_CLI_REPO/install.sh" || true
  echo "  ✓ dev-cli installed"
else
  echo "  ! dev-cli repo not found at $DEV_CLI_REPO — install manually"
fi

# Link shared secrets
SHARED_SECRETS="/etc/dev-cli/secrets"
USER_CONFIG="/home/$USERNAME/.config/dev-cli/secrets"
if [ -d "$SHARED_SECRETS" ]; then
  mkdir -p "$USER_CONFIG"
  for secret_file in "$SHARED_SECRETS"/*; do
    local_name=$(basename "$secret_file")
    ln -sf "$secret_file" "$USER_CONFIG/$local_name"
  done
  chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config/dev-cli"
  echo "  ✓ Shared secrets linked"
else
  echo "  ! No shared secrets at $SHARED_SECRETS — create them first"
fi

# Ensure .bashrc sources nvm
if [ -d "/home/$USERNAME/.nvm" ] || [ -d "$HOME/.nvm" ]; then
  if ! grep -q 'NVM_DIR' "/home/$USERNAME/.bashrc" 2>/dev/null; then
    cat >> "/home/$USERNAME/.bashrc" << 'NVM_INIT'

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
NVM_INIT
    echo "  ✓ nvm sourced in .bashrc"
  fi
fi

echo ""
echo "Done! Next steps for $USERNAME:"
echo "  1. Ensure the user is on your Tailscale tailnet"
echo "  2. User logs in:  ssh $USERNAME@<tailscale-hostname>"
echo "  3. User runs:     dev doctor"
ADD_USER_SCRIPT
sudo chmod +x /usr/local/bin/add-dev-user
log "add-dev-user helper installed at /usr/local/bin/add-dev-user"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo -e "  ${GREEN}Bootstrap complete!${NC}"
echo "============================================"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Log out and back in (for Docker group + PATH changes):"
echo "     $ exit"
echo "     $ ssh user@your-vps"
echo ""
echo "  2. Connect Tailscale:"
echo "     $ sudo tailscale up --ssh"
echo ""
echo "  3. Add your API keys:"
echo "     $ nano ~/.config/dev-cli/secrets.env"
echo ""
echo "  4. Set up your first project:"
echo "     $ dev setup klyra git@github.com:yourorg/klyra.git"
echo ""
echo "  5. Spin up an agent:"
echo "     $ dev new klyra feat/my-feature --agent claude"
echo ""
echo "============================================"
