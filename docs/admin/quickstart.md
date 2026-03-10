# Admin Quickstart

Get dev-cli running on a fresh VPS in 10 minutes.

## Prerequisites

- Ubuntu 22.04+ or Debian 12+ VPS (4GB+ RAM recommended)
- A Tailscale account (free tier works)
- SSH access to the VPS

## Step 1: Bootstrap the Server

Bootstrap must run as a **non-root user**. If your VPS only has root, create your admin user first:

```bash
# As root:
adduser <your-username>
usermod -aG sudo <your-username>
su - <your-username>
```

Then run bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/theholdinco/dev-cli/main/bootstrap.sh | bash
```

This installs all system dependencies (Docker, tmux, git, jq, Tailscale, authbind, etc.) and sets up the multi-user infrastructure.

## Step 2: Connect Tailscale

```bash
sudo tailscale up
```

Follow the link to authenticate. Note your Tailscale IP:

```bash
tailscale ip -4
```

## Step 3: Add Your Admin Account

```bash
dev admin add-user $(whoami) --tailscale-email your@email.com --role admin
```

## Step 4: Add Your First User

```bash
dev admin add-user alice --tailscale-email alice@company.com --role user
```

This outputs onboarding instructions to send to the user.

## Step 5: Verify

```bash
dev admin list-users
dev admin status
dev doctor
```

## Next Steps

- [User Management](user-management.md) — add/remove/suspend users
- [Security](security.md) — how identity binding and port isolation work
- [Configuration](configuration.md) — hooks, templates, shared secrets
