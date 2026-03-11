#!/usr/bin/env bash
###############################################################################
# VPS Bootstrap Script
# Run on a blank Ubuntu VPS to set up a multi-agent development environment.
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

# Homebrew and nvm can't install as root
if [ "$(id -u)" -eq 0 ]; then
  err "Don't run bootstrap.sh as root!"
  echo ""
  echo "  Create a user first, then run as that user:"
  echo "    adduser <username>"
  echo "    usermod -aG sudo <username>"
  echo "    su - <username>"
  echo "    cd /opt/dev-cli && ./bootstrap.sh"
  echo ""
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. GitHub CLI (needed early for cloning private repos)
# ---------------------------------------------------------------------------
if command -v gh &>/dev/null; then
  log "GitHub CLI already installed"
else
  info "Installing GitHub CLI..."
  (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update && sudo apt install gh -y
  log "GitHub CLI installed"
fi

# ---------------------------------------------------------------------------
# 2. System packages
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
  btop \
  tree \
  ripgrep \
  fd-find \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  python3 \
  python3-pip \
  python3-venv \
  pkg-config \
  libssl-dev \
  file \
  procps

info "Installing authbind..."
sudo apt-get install -y authbind

log "System packages installed"

# ---------------------------------------------------------------------------
# 2b. Shared multi-user infrastructure
# ---------------------------------------------------------------------------
info "Setting up shared multi-user infrastructure..."
sudo groupadd -f devs
sudo usermod -aG devs "$USER"
sudo mkdir -p /etc/dev-cli
sudo chown :devs /etc/dev-cli
sudo chmod g+ws /etc/dev-cli
if [ ! -f /etc/dev-cli/ports.json ]; then
  echo '{}' | sudo tee /etc/dev-cli/ports.json > /dev/null
  sudo chown :devs /etc/dev-cli/ports.json
  sudo chmod g+w /etc/dev-cli/ports.json
fi
if [ ! -f /etc/dev-cli/users.json ]; then
  echo '{"users":{}}' | sudo tee /etc/dev-cli/users.json > /dev/null
  sudo chown :devs /etc/dev-cli/users.json
  sudo chmod g+w /etc/dev-cli/users.json
fi
if [ ! -f /etc/dev-cli/audit.log ]; then
  sudo touch /etc/dev-cli/audit.log
  sudo chown :devs /etc/dev-cli/audit.log
  sudo chmod g+w /etc/dev-cli/audit.log
fi
log "Shared infrastructure ready (/etc/dev-cli, devs group)"

# ---------------------------------------------------------------------------
# 3. Homebrew
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
# 4. Node.js (system-wide via NodeSource)
# ---------------------------------------------------------------------------
if command -v node &>/dev/null; then
  log "Node.js already installed: $(node --version)"
else
  info "Installing Node.js LTS (system-wide)..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt install -y nodejs
  log "Node.js $(node --version) installed (system-wide)"
fi

# Install global npm packages (system-wide)
info "Installing global npm packages..."
sudo npm install -g pnpm yarn typescript ts-node
log "Global npm packages installed"

# ---------------------------------------------------------------------------
# 5. Docker
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
# 6. Firewall (ufw)
# ---------------------------------------------------------------------------
if command -v ufw &>/dev/null; then
  info "Configuring firewall..."
  # Allow SSH on public interface (so you don't lock yourself out)
  sudo ufw allow OpenSSH
  # Allow Tailscale interface (all traffic within tailnet is trusted)
  sudo ufw allow in on tailscale0
  # Enable firewall (idempotent)
  sudo ufw --force enable
  log "Firewall enabled: SSH + Tailscale allowed, all other inbound blocked"
else
  info "Installing ufw..."
  sudo apt install -y ufw
  sudo ufw allow OpenSSH
  sudo ufw allow in on tailscale0
  sudo ufw --force enable
  log "Firewall installed and enabled"
fi

# ---------------------------------------------------------------------------
# 7. Tailscale
# ---------------------------------------------------------------------------
if command -v tailscale &>/dev/null; then
  log "Tailscale already installed"
else
  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  log "Tailscale installed"
  warn "Run 'sudo tailscale up --ssh' to connect to your Tailscale network"
fi

# Install SSH identity binding
SCRIPT_DIR_BS="$(cd "$(dirname "$0")" && pwd)"
# When run via curl | bash, fall back to the cloned repo location
[ -f "$SCRIPT_DIR_BS/ssh/validate-tailscale-identity.sh" ] || SCRIPT_DIR_BS="/opt/dev-cli"
if [ -f "$SCRIPT_DIR_BS/ssh/validate-tailscale-identity.sh" ]; then
  info "Setting up SSH identity binding..."
  sudo cp "$SCRIPT_DIR_BS/ssh/validate-tailscale-identity.sh" /usr/local/bin/validate-tailscale-identity
  sudo chmod 755 /usr/local/bin/validate-tailscale-identity

  # Configure sshd to use the validation script
  sudo mkdir -p /etc/ssh/sshd_config.d
  if ! grep -q "validate-tailscale-identity" /etc/ssh/sshd_config.d/dev-cli.conf 2>/dev/null; then
    sudo tee /etc/ssh/sshd_config.d/dev-cli.conf > /dev/null <<'SSHEOF'
# dev-cli: Tailscale identity validation
AuthorizedKeysCommand /usr/local/bin/validate-tailscale-identity %u
AuthorizedKeysCommandUser root
SSHEOF
    sudo systemctl reload sshd 2>/dev/null || true
  fi
  log "SSH identity binding configured"
fi

# Harden SSH: disable password auth for local connections
info "Hardening SSH configuration..."
sudo mkdir -p /etc/ssh/sshd_config.d
if [ ! -f /etc/ssh/sshd_config.d/dev-cli-hardening.conf ]; then
  sudo tee /etc/ssh/sshd_config.d/dev-cli-hardening.conf > /dev/null <<'SSHEOF'
# dev-cli: Prevent cross-user access
# Disable local password auth (prevents su/ssh localhost attacks)
Match Address 127.0.0.1,::1
    PasswordAuthentication no
    KbdInteractiveAuthentication no
SSHEOF
fi

# Restrict su to root only
info "Restricting su access..."
sudo dpkg-statoverride --update --add root adm 4750 /bin/su 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8. tmux
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
# 9. Supabase CLI
# ---------------------------------------------------------------------------
if command -v supabase &>/dev/null; then
  log "Supabase CLI already installed"
else
  info "Installing Supabase CLI..."
  brew install supabase/tap/supabase
  log "Supabase CLI installed"
fi

# ---------------------------------------------------------------------------
# 10. lazygit
# ---------------------------------------------------------------------------
if command -v lazygit &>/dev/null; then
  log "lazygit already installed"
else
  info "Installing lazygit..."
  # Install system-wide so all users get it
  LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
  sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
  rm /tmp/lazygit.tar.gz
  log "lazygit installed (system-wide)"
fi

# ---------------------------------------------------------------------------
# 11. delta (git pager)
# ---------------------------------------------------------------------------
if command -v delta &>/dev/null; then
  log "delta already installed"
else
  info "Installing delta..."
  # Install system-wide so all users get it
  DELTA_VERSION=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
  curl -Lo /tmp/delta.deb "https://github.com/dandavison/delta/releases/latest/download/git-delta_${DELTA_VERSION}_amd64.deb"
  sudo dpkg -i /tmp/delta.deb
  rm /tmp/delta.deb
  log "delta installed (system-wide)"
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
# 12. Codex CLI (system-wide via npm)
# ---------------------------------------------------------------------------
if command -v codex &>/dev/null; then
  log "Codex CLI already installed"
else
  info "Installing Codex CLI..."
  sudo npm install -g @openai/codex
  log "Codex CLI installed (system-wide)"
fi

# ---------------------------------------------------------------------------
# 13b. Claude Code (per-user install for the bootstrapping admin)
# ---------------------------------------------------------------------------
if command -v claude &>/dev/null; then
  log "Claude Code already installed"
else
  info "Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | sh; then
    log "Claude Code installed — run 'claude' to authenticate"
  else
    warn "Claude Code install failed — run manually: curl -fsSL https://claude.ai/install.sh | sh"
  fi
fi

# ---------------------------------------------------------------------------
# 14. Directory structure
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
# 15. Install the `dev` CLI
# ---------------------------------------------------------------------------
info "Installing dev CLI..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_CLI_REPO="/opt/dev-cli"
if [ -f "$SCRIPT_DIR/install.sh" ]; then
  # Running from a cloned repo
  echo N | bash "$SCRIPT_DIR/install.sh"
else
  # Running via curl | bash — clone the repo first
  # Allow overriding branch via DEV_CLI_BRANCH env var (default: main)
  DEV_CLI_BRANCH="${DEV_CLI_BRANCH:-main}"
  info "Cloning dev-cli ($DEV_CLI_BRANCH) to $DEV_CLI_REPO..."
  if [ -d "$DEV_CLI_REPO" ]; then
    info "Repo already exists at $DEV_CLI_REPO, pulling latest..."
    git -C "$DEV_CLI_REPO" fetch origin
    git -C "$DEV_CLI_REPO" checkout "$DEV_CLI_BRANCH"
    git -C "$DEV_CLI_REPO" pull --ff-only
  else
    sudo git clone -b "$DEV_CLI_BRANCH" https://github.com/theholdinco/dev-cli.git "$DEV_CLI_REPO"
    sudo chown -R "$USER:$USER" "$DEV_CLI_REPO"
  fi
  echo N | bash "$DEV_CLI_REPO/install.sh"
fi
log "dev CLI installed"

# ---------------------------------------------------------------------------
# 15b. Register bootstrapping user as admin
# ---------------------------------------------------------------------------
_USERS_FILE="/etc/dev-cli/users.json"
if [ -f "$_USERS_FILE" ]; then
  _user_count=$(jq '.users | length' "$_USERS_FILE" 2>/dev/null || echo "0")
  if [ "$_user_count" -eq 0 ]; then
    info "Registering $USER as admin in the user registry..."
    _now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    _tmp=$(mktemp)
    jq --arg u "$USER" --arg t "$_now" \
      '.users[$u] = {"tailscale_email": "", "role": "admin", "created": $t, "status": "active", "max_sessions": 8, "onboarded": false}' \
      "$_USERS_FILE" > "$_tmp" \
      && sudo cp "$_tmp" "$_USERS_FILE" \
      && sudo chown ":devs" "$_USERS_FILE" \
      && sudo chmod g+w "$_USERS_FILE" \
      && rm -f "$_tmp"
    log "$USER registered as admin. Set your Tailscale email with:"
    info "  dev admin add-user $USER --tailscale-email your@email.com --role admin"
  else
    info "User registry already has $_user_count user(s) — skipping auto-registration"
  fi
fi

# ---------------------------------------------------------------------------
# 16. Shell enhancements
# ---------------------------------------------------------------------------
info "Adding shell aliases and helpers..."
cat >> ~/.bashrc << 'BASHRC'

# ── Terminal compatibility ─────────────────────────────────
# Fix for terminals like Ghostty whose $TERM isn't in remote terminfo
if ! infocmp "$TERM" &>/dev/null 2>&1; then
  export TERM=xterm-256color
fi

# ── Dev CLI shortcuts ───────────────────────────────────────
alias d="dev"
alias dl="dev ls"
alias da="dev attach"
alias dk="dev kill"
alias dh="dev hub"

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
# 17. API keys placeholder
# ---------------------------------------------------------------------------
if [ ! -f ~/.config/dev-cli/secrets.env ]; then
  info "Creating API keys placeholder..."
  cat > ~/.config/dev-cli/secrets.env << 'SECRETS'
# API Keys — chmod 600 this file
# These are sourced by the dev CLI when launching agents

# Claude Code — pick ONE (not both):
# CLAUDE_CODE_OAUTH_TOKEN=    # Pro/Max subscription (run: claude setup-token)
# ANTHROPIC_API_KEY=sk-ant-... # API key (pay-per-token billing)

# Codex (OpenAI)
# OPENAI_API_KEY=sk-...
SECRETS
  chmod 600 ~/.config/dev-cli/secrets.env
  log "API keys file created at ~/.config/dev-cli/secrets.env"
  warn "Edit ~/.config/dev-cli/secrets.env with your API keys"
fi

# ---------------------------------------------------------------------------
# 18. Multi-user helper (add-dev-user)
# ---------------------------------------------------------------------------
info "Installing add-dev-user stub (deprecated — use 'dev admin add-user' instead)..."
sudo tee /usr/local/bin/add-dev-user > /dev/null << 'STUB_SCRIPT'
#!/usr/bin/env bash
echo "add-dev-user is deprecated. Use: dev admin add-user <username> --tailscale-email <email>"
exit 1
STUB_SCRIPT
sudo chmod +x /usr/local/bin/add-dev-user
warn "add-dev-user is now a stub. Use 'dev admin add-user' for multi-user setup."

# ---------------------------------------------------------------------------
# 19. Web dashboard & bot services
# ---------------------------------------------------------------------------
info "Setting up web dashboard and bot services..."
WEB_DIR="$HOME/.local/share/dev-cli/web"
VENV_DIR="$HOME/.config/dev-cli/venv"

if [ -d "$WEB_DIR" ] && [ -f "$WEB_DIR/requirements.txt" ]; then
  if [ ! -d "$VENV_DIR" ]; then
    info "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
  fi
  info "Installing Python dependencies..."
  "$VENV_DIR/bin/pip" install -q -r "$WEB_DIR/requirements.txt"
  log "Python venv ready"

  # Install systemd services (auto-start on boot)
  info "Installing systemd services..."
  "$HOME/.local/bin/dev" services install 2>/dev/null || \
    warn "Could not install services automatically. Run 'dev services install' after login."
else
  warn "Web dashboard files not found — run install.sh first, then 'dev services install'"
fi

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
echo "     $ dev init"
echo ""
echo "  5. Spin up an agent:"
echo "     $ dev new <project> feat/my-feature --agent claude"
echo ""
echo "  Web dashboard and Telegram bot services are installed"
echo "  and will auto-start on boot. Check status with:"
echo "     $ dev services status"
echo ""
echo "============================================"
