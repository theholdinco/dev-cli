# dev-cli

Manage multiple AI coding agent instances on a shared VPS. Built for dev teams.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/theholdinco/dev-cli/main/bootstrap.sh | bash
```

## Documentation

**Admins:** [Quickstart](docs/admin/quickstart.md) · [User Management](docs/admin/user-management.md) · [Security](docs/admin/security.md) · [Configuration](docs/admin/configuration.md) · [Troubleshooting](docs/admin/troubleshooting.md)

**Users:** [Getting Started](docs/user/getting-started.md) · [Daily Workflow](docs/user/daily-workflow.md) · [Commands](docs/user/commands.md) · [Tips](docs/user/tips.md) · [FAQ](docs/user/faq.md)

## What It Does

- Manages isolated git worktrees per coding session
- Allocates dedicated ports (frontend, backend, Supabase)
- Runs AI agents (Claude Code, Codex) in persistent tmux sessions
- Multi-user with Tailscale identity binding and role-based access
- Interactive TUI dashboard and Telegram notifications
