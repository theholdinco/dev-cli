# Team Setup Guide

Multi-user dev-cli setup on a shared VPS. Supports 50 concurrent sessions across multiple engineers.

## VPS Admin (One-Time)

### 1. Provision Server

Recommended: Hetzner AX42 (~$49/mo, 8c/16t, 64GB RAM). Any Ubuntu 22.04+ server works.

### 2. Install GitHub CLI & Bootstrap

```bash
# Create your user first (don't run bootstrap as root!)
adduser mrg
usermod -aG sudo mrg
su - mrg

# Install gh
sudo apt update && sudo apt install gh -y

# Authenticate and clone
gh auth login              # select HTTPS when prompted
sudo git clone https://github.com/your-org/dev-cli.git /opt/dev-cli
sudo chown -R $USER:$USER /opt/dev-cli

# Run bootstrap (must NOT be root — needs sudo access though)
cd /opt/dev-cli
./bootstrap.sh
```

### 3. Connect Tailscale

```bash
sudo tailscale up --ssh
```

### 4. Create Shared Secrets

```bash
sudo mkdir -p /etc/dev-cli/secrets
sudo nano /etc/dev-cli/secrets/patagon.env
sudo chmod 600 /etc/dev-cli/secrets/patagon.env
```

Required keys in `patagon.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
SUPABASE_JWT_SECRET=...
DOCUSIGN_CLIENT_ID=...
DOCUSIGN_CLIENT_SECRET=...
DOCUSIGN_ACCOUNT_ID=...
SUMSUB_APP_TOKEN=...
SUMSUB_SECRET_KEY=...
RESEND_API_KEY=...
```

### 5. Add Engineers

```bash
sudo add-dev-user alice
sudo add-dev-user bob
```

Each engineer must be on your Tailscale tailnet. Tailscale SSH handles authentication — no SSH keys needed.

### 6. Backfill Existing Sessions (Migration)

If upgrading from single-user, backfill the `owner` field:

```bash
jq --arg user "$USER" 'to_entries | map(.value.owner //= $user) | from_entries' \
  ~/.config/dev-cli/ports.json > /tmp/ports.json && mv /tmp/ports.json ~/.config/dev-cli/ports.json
```

---

## Each Engineer (Onboarding)

### 1. Join Tailnet

Install Tailscale on your machine and join the team's tailnet. No SSH keys needed — Tailscale handles auth.

### 2. SSH to VPS

```bash
ssh <your-username>@<tailscale-hostname>
```

### 3. Authenticate with GitHub

```bash
gh auth login
```

Select HTTPS when prompted. This authenticates both `gh` CLI (for PRs) and Git operations (push/pull) — no SSH keys needed.

### 4. Install & Authenticate Your AI Agent

```bash
# Claude Code (per-user install + login)
curl -fsSL https://claude.ai/install.sh | bash
claude login

# Codex (already installed system-wide, just log in)
codex login
```

### 5. Verify Setup

```bash
dev doctor
```

### 6. Set Up Project

```bash
dev setup patagon git@github.com:your-org/patagon.git
```

---

## Daily Workflow

### Start a Session

```bash
dev new patagon feat/my-feature --agent claude
```

This creates a git worktree, generates `.env` files via the repo's `.dev/setup.sh` hook, installs dependencies, and launches Claude Code in a tmux session with 3 windows (agent, shell, server).

### List Sessions

```bash
dev ls              # your sessions only
dev ls --all        # all team sessions
```

### Attach From Any Device

```bash
dev attach feat-my  # partial match works
```

Works from mobile via Tailscale SSH + tmux.

### Interactive Hub

```bash
dev hub
```

TUI dashboard with session list, live preview, and keyboard shortcuts. Press `[a]` to toggle between your sessions and all sessions.

### Clean Up

```bash
dev kill feat-my    # kill a session
dev gc              # clean up dead sessions
```

### Create PR

```bash
dev pr feat-my      # push, create PR, optionally kill session
```

---

## Conventions

- **Session naming:** `project-branch` (e.g., `patagon-feat-auth`). Owner is metadata, not part of the name.
- **Port allocation:** Each session gets a slot (1-50) with dedicated ports (frontend 3001-3050, backend 4001-4050).
- **Setup hooks:** The repo's `.dev/setup.sh` runs automatically on `dev new`. It generates the right `.env` files per package.
- **Shared Supabase:** All sessions share the same hosted Supabase instance. Migrations are coordinated manually.
- **Killing other users' sessions:** Prompts for confirmation.
