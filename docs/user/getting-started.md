# Getting Started

Your admin has set up a dev server for you. Here's how to connect and start working.

## Step 1: Install Tailscale

Download Tailscale for your platform: https://tailscale.com/download

Sign in with the account your admin registered you with.

## Step 2: Connect via SSH

```bash
ssh <your-username>@<server-hostname>
```

Your admin will give you the hostname and a temporary password. You'll be asked to change it on first login.

## Step 3: Set Up Your Account

```bash
dev setup-account
```

This walks you through:
- Verifying your Tailscale connection
- Authenticating GitHub (`gh auth login`)
- Authenticating Claude Code (`claude login`)
- Running a health check

## Step 4: Initialize a Project

```bash
dev init <project-name>
```

Or if the project isn't set up yet:

```bash
dev setup <project-name> <git-url>
```

## Step 5: Start Your First Session

```bash
dev new my-feature --agent claude
```

This creates an isolated workspace with its own git branch and dedicated ports.

## Step 6: Open the Dashboard

```bash
dev hub
```

The dashboard shows all your sessions with keyboard shortcuts for common actions.

## Next Steps

- [Daily Workflow](daily-workflow.md) — common patterns
- [Commands](commands.md) — full reference
- [Tips](tips.md) — mobile access, shortcuts
