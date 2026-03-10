# Configuration

How to configure projects, hooks, templates, and shared secrets.

## Setup Hooks

For monorepo projects (multiple packages each needing their own `.env`), use a setup hook instead of an env template.

**Location:** `~/.config/dev-cli/hooks/<project>/setup.sh`

The hook is an executable bash script that runs after each worktree is created. It receives port and path information via environment variables:

| Variable | Example | Description |
|---|---|---|
| `DEV_SLOT` | `3` | Slot number (1-50) |
| `DEV_WORKTREE` | `/home/user/projects/project-worktrees/feat-auth` | Absolute path to worktree |
| `DEV_FRONTEND_PORT` | `3003` | Frontend port |
| `DEV_BACKEND_PORT` | `4003` | Backend port |
| `DEV_SUPA_API_PORT` | `54341` | Supabase API port |
| `DEV_SUPA_DB_PORT` | `54342` | Supabase DB port |
| `DEV_SUPA_STUDIO_PORT` | `54343` | Supabase Studio port |
| `DEV_IP` | `100.64.0.5` | Tailscale IP |

**Example hook:**

```bash
#!/usr/bin/env bash
set -euo pipefail

cat > "$DEV_WORKTREE/apps/web/.env" << EOF
PORT=$DEV_FRONTEND_PORT
NEXT_PUBLIC_SUPABASE_URL=http://localhost:$DEV_SUPA_API_PORT
EOF

cat > "$DEV_WORKTREE/apps/api/.env" << EOF
PORT=$DEV_BACKEND_PORT
DATABASE_URL=postgresql://postgres:postgres@localhost:$DEV_SUPA_DB_PORT/postgres
EOF
```

Make it executable: `chmod +x ~/.config/dev-cli/hooks/<project>/setup.sh`

To edit an existing hook: `dev template <project>`

See [`examples/monorepo-hook.sh`](../../examples/monorepo-hook.sh) for a full example.

## Env Templates

For standard (non-monorepo) projects with a single `.env` file.

**Location:** `~/.config/dev-cli/templates/<project>.env`

Templates use `{{PLACEHOLDER}}` syntax for values that vary per session:

```bash
PORT={{FRONTEND_PORT}}
NEXT_PUBLIC_PORT={{FRONTEND_PORT}}
BACKEND_PORT={{BACKEND_PORT}}
NEXT_PUBLIC_SUPABASE_URL=http://localhost:{{SUPA_API_PORT}}
MY_API_KEY=sk-hardcoded-value-here
```

**Available placeholders:**
- `{{FRONTEND_PORT}}` — frontend port (3001-3050)
- `{{BACKEND_PORT}}` — backend port (4001-4050)
- `{{SUPA_API_PORT}}` — Supabase API port
- `{{SUPA_DB_PORT}}` — Supabase DB port
- `{{SUPA_STUDIO_PORT}}` — Supabase Studio port
- `{{SLOT}}` — slot number (1-50)
- `{{IP}}` — Tailscale IP

When `dev new` creates a session, it copies the template into the worktree as `.env.local`, replacing all placeholders with actual values.

To edit a template: `dev template <project>`

## Hook Priority

When `dev new` creates a session, it looks for setup configuration in this order:

1. **In-repo hook** — `.dev/setup.sh` inside the repository (checked into git)
2. **Global hook** — `~/.config/dev-cli/hooks/<project>/setup.sh`
3. **Env template** — `~/.config/dev-cli/templates/<project>.env`

## Shared Secrets

Team API keys that should be available to all users live in `/etc/dev-cli/secrets/`.

**Adding a shared secret:**

```bash
sudo nano /etc/dev-cli/secrets/myproject.env
sudo chmod 640 /etc/dev-cli/secrets/myproject.env
sudo chown root:devs /etc/dev-cli/secrets/myproject.env
```

Files here are automatically symlinked into each user's `~/.config/dev-cli/secrets/` when they're added via `dev admin add-user`. For existing users, run:

```bash
dev admin sync-secrets <username>
dev admin sync-secrets --all
```

## Project Configuration

Project metadata lives in `~/.config/dev-cli/projects/<project>.json`. This is created and managed by `dev init` and `dev setup`. It stores the project's git URL, worktree base path, and other settings.

To list configured projects:

```bash
dev projects
```

## Global Config

`~/.config/dev-cli/config.json` holds user-level CLI settings:

```json
{
  "default_agent": "claude",
  "telegram_chat_id": "12345",
  "notify_on_complete": true
}
```

Most settings are managed through `dev setup-account` and individual command flags rather than editing this file directly.

## Stale Session Cleanup

Sessions that have been idle for a long time waste slots and ports.

**Manual cleanup:**

```bash
dev admin stale-sessions --older-than 7d         # list stale sessions
dev admin stale-sessions --older-than 7d --kill  # kill them
```

**Automated cleanup (optional):**

Add a cron job on the server:

```bash
sudo crontab -e
```

```
# Kill sessions older than 14 days, daily at 3am
0 3 * * * /usr/local/bin/dev admin stale-sessions --older-than 14d --kill --quiet
```

The `--quiet` flag suppresses output (appropriate for cron). Killed sessions are logged to `/etc/dev-cli/audit.log`.
