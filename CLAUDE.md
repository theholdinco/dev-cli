# CLAUDE.md

## What this project is

`dev-cli` is a bash-based CLI tool for managing multiple AI coding agent instances (Claude Code, Codex) on a remote VPS. It manages git worktrees, tmux sessions, port allocation, and environment configuration.

## Architecture

- **`bin/dev`** — Main CLI entrypoint (~1400 lines bash). All commands route through a case statement at the bottom. Uses `jq` for JSON state management in `~/.config/dev-cli/ports.json`.
- **`bin/dev-hub`** — Interactive TUI that runs inside tmux. Renders a dashboard with session list, preview pane, and keyboard shortcuts. Auto-refreshes every 5 seconds.
- **`bootstrap.sh`** — One-time VPS setup script. Installs all system dependencies.
- **`install.sh`** — Installs just the dev-cli binaries and config structure.

## Key concepts

- **Slots (1-5):** Each active session gets a slot which determines its ports (frontend 3001-3005, backend 4001-4005, Supabase 54321/54331/etc.)
- **Port registry:** `~/.config/dev-cli/ports.json` tracks all active sessions, their slots, ports, paths, and metadata.
- **Setup hooks:** Monorepo projects use executable bash scripts at `~/.config/dev-cli/hooks/<project>/setup.sh` instead of env templates. These receive port info via environment variables (`DEV_FRONTEND_PORT`, etc.)
- **Env templates:** Standard (non-monorepo) projects use `.env` template files with `{{PLACEHOLDER}}` syntax at `~/.config/dev-cli/templates/<project>.env`.

## Code conventions

- Pure bash (no Python, no Node for the CLI itself)
- `set -euo pipefail` at the top of every script
- Color output via ANSI escape codes (RED, GREEN, BLUE, etc. variables)
- Functions prefixed with `cmd_` are command handlers
- Helper functions (get_session_field, slot_ports, etc.) are defined before commands
- jq for all JSON manipulation
- Partial name matching for session references (user can type `dev attach feat` instead of full name)

## Testing changes

After editing, verify syntax with:
```bash
bash -n bin/dev && echo "OK"
bash -n bin/dev-hub && echo "OK"
```

To install locally after changes:
```bash
./install.sh
```

## Common tasks

- **Adding a new command:** Add `cmd_<name>()` function, add to the case statement at the bottom of `bin/dev`, add to `cmd_help()`, optionally add a keyboard shortcut in `bin/dev-hub`.
- **Changing port scheme:** Modify the `BASE_*_PORT` variables and `slot_ports()` function in `bin/dev`.
- **Adding hub features:** Edit `bin/dev-hub` — add an `action_<name>()` function, add the key handler in the main loop case statement, update the footer render.
