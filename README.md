# dev-cli

A bash-based CLI tool for managing multiple AI coding agent instances (Claude Code, Codex) on a remote VPS. Provides isolated git worktrees, automatic port allocation, tmux session management, and an interactive TUI control center.

## Architecture

```
┌───────────────────────────────────────────────────┐
│                 Hetzner VPS (24/7)                 │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │              tmux sessions                   │  │
│  │                                             │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐      │  │
│  │  │ claude  │ │ codex   │ │ claude  │ ×5   │  │
│  │  │ :3001   │ │ :3002   │ │ :3003   │      │  │
│  │  │ feat/ui │ │ fix/bug │ │ refactor│      │  │
│  │  └─────────┘ └─────────┘ └─────────┘      │  │
│  └─────────────────────────────────────────────┘  │
│                                                   │
│  Tailscale: 100.x.x.x                            │
└───────────────────────────────────────────────────┘
         │
    ┌────┴────┐    ┌────────┐    ┌────────┐
    │ MacBook │    │ Phone  │    │Laptop 2│
    │ Ghostty │    │Termius │    │  SSH   │
    └─────────┘    └────────┘    └────────┘
```

## Quick Start

```bash
# Clone this repo on your VPS
git clone git@github.com:YOUR_ORG/dev-cli.git ~/.dev-cli-repo
cd ~/.dev-cli-repo

# Install (copies binaries, sets up config)
./install.sh

# Full VPS bootstrap (brew, node, docker, tmux, tailscale, etc.)
./bootstrap.sh

# Set up your first project
dev init

# Launch an agent
dev new myproject feat/cool-feature --agent claude

# Open the TUI hub
dev hub
```

## Commands

### Setup
| Command | Description |
|---------|-------------|
| `dev init` | Interactive project setup (recommended) |
| `dev setup <project> <url>` | Quick bare clone setup |
| `dev projects` | List configured projects |

### Sessions
| Command | Description |
|---------|-------------|
| `dev new <project> <branch> [--agent claude\|codex\|none]` | Create worktree + launch agent |
| `dev ls` | List all active sessions |
| `dev attach [session]` | Attach to session (interactive picker) |
| `dev kill <session>` | Stop agent, remove worktree, free ports |
| `dev hub` | Interactive TUI control center |
| `dev dashboard` | Split-pane view of all agents |

### Finish & Merge
| Command | Description |
|---------|-------------|
| `dev pr <session>` | Push, create PR, optionally kill session |
| `dev pr <session> --draft` | Create as draft PR |
| `dev pr <session> --kill` | Auto-kill after PR creation |

### Utilities
| Command | Description |
|---------|-------------|
| `dev ports` | Show port allocation table |
| `dev url <session>` | Print Tailscale URLs |
| `dev logs <session>` | Show recent agent output |
| `dev shell <session>` | Open shell in worktree |
| `dev worktree <project> <branch>` | Create worktree without agent |

### Supabase
| Command | Description |
|---------|-------------|
| `dev supabase <session> start` | Start local Supabase (auto-fills keys) |
| `dev supabase <session> stop` | Stop Supabase |
| `dev supabase <session> reset` | Reset database |

### Images
| Command | Description |
|---------|-------------|
| `dev img ls` | List uploaded images |
| `dev img cp <session> <file>` | Copy image to worktree |
| `dev img grab <url>` | Download image from URL |

## Hub TUI

`dev hub` opens an interactive control center:

```
  DEV HUB                                      10:32

  3 active sessions · 100.x.x.x

  [1] ● klyra-feat-auth          claude    :3001
  [2] ● klyra-fix-bug            codex     :3002
  [3] ○ (available)
  [4] ○ (available)
  [5] ○ (available)

  ── Preview: klyra-feat-auth ──────────────────
  │ Analyzing the trading module...
  │ Created file: src/components/Trade.tsx

  [1-5] select  [Enter] attach  [n]ew  [k]ill  [p]orts
  [m]erge/PR  [l]azygit  [s]hell  [u]rl  [r]efresh  [q]uit
```

## Port Allocation

Each session gets an isolated set of ports:

| Slot | Frontend | Backend | Supabase API | Supabase DB | Supabase Studio |
|------|----------|---------|-------------|-------------|-----------------|
| 1 | 3001 | 4001 | 54321 | 54322 | 54323 |
| 2 | 3002 | 4002 | 54331 | 54332 | 54333 |
| 3 | 3003 | 4003 | 54341 | 54342 | 54343 |
| 4 | 3004 | 4004 | 54351 | 54352 | 54353 |
| 5 | 3005 | 4005 | 54361 | 54362 | 54363 |

Access frontends from any Tailscale device: `http://100.x.x.x:3001`

## Monorepo Support

For monorepos with multiple `packages/` that need separate `.env` files, `dev init` generates a setup hook at `~/.config/dev-cli/hooks/<project>/setup.sh`. This runs after every worktree creation and has access to all port variables:

```bash
# Available in setup hooks:
$DEV_SLOT             # 1-5
$DEV_FRONTEND_PORT    # 3001-3005
$DEV_BACKEND_PORT     # 4001-4005
$DEV_SUPA_API_PORT    # Supabase API port
$DEV_SUPA_DB_PORT     # Supabase DB port
$DEV_SUPA_STUDIO_PORT # Supabase Studio port
$DEV_WORKTREE         # /home/user/projects/project-worktrees/branch
$DEV_IP               # Tailscale IP
```

See [`examples/monorepo-hook.sh`](examples/monorepo-hook.sh) for a full example.

## Mac-Side Helpers

Add to your `~/.zshrc` for image upload support:

```bash
source /path/to/dev-cli/extras/vpsimg.zshrc
```

Commands:
- `vpsimg ~/Desktop/screenshot.png` — upload to VPS, copy path to clipboard
- `vpsimg ~/Desktop/mockup.png klyra-feat-auth` — upload directly to worktree
- `vpsclip` — upload screenshot from clipboard

## File Structure

```
~/.config/dev-cli/
├── ports.json              # Active session registry
├── secrets.env             # API keys (chmod 600)
├── secrets/                # Per-project secrets
│   └── klyra.env
├── templates/              # Env templates (standard repos)
│   └── myproject.env
├── hooks/                  # Setup hooks (monorepos)
│   └── klyra/
│       └── setup.sh
├── projects/               # Project configs
│   └── klyra.json
└── logs/

~/projects/
├── klyra/                  # Bare git repo
├── klyra-worktrees/        # Worktrees
│   ├── feat-auth/
│   └── fix-bug/
└── other-project/
```

## Feature Lifecycle

```bash
dev new klyra feat/trading --agent claude   # 1. Create
dev hub                                      # 2. Monitor
dev attach klyra-feat-trading               # 3. Review
dev pr klyra-feat-trading                    # 4. PR
dev kill klyra-feat-trading                  # 5. Cleanup
```

## Updating

```bash
cd ~/.dev-cli-repo
git pull
./install.sh
```

## Requirements

- Ubuntu 22.04+ (tested on 24.04)
- `gh` CLI (GitHub)
- `jq`
- Docker (for local Supabase)
- Tailscale (for remote access)

All other dependencies are installed by `bootstrap.sh`.

## tmux Cheatsheet

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach (session keeps running) |
| `Ctrl+b s` | Switch between sessions |
| `Ctrl+b 1/2/3` | Switch window (agent/shell/server) |
| `Ctrl+b z` | Zoom pane (fullscreen toggle) |
| `Ctrl+b \|` | Split vertically |
| `Ctrl+b -` | Split horizontally |
| `Alt+↑↓←→` | Move between panes |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Verify syntax after changes: `bash -n bin/dev && bash -n bin/dev-hub`
4. Test locally with `./install.sh`
5. Submit a pull request
