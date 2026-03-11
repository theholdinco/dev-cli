# Tips and Tricks

## Mobile Access

### Setting Up Tailscale on Mobile

Install Tailscale on iOS or Android from the App Store / Google Play. Sign in with the same account your admin registered you with. Once connected, the VPS will appear in your Tailscale network.

### SSH Client: Termius

[Termius](https://termius.com/) works well on both iOS and Android:

1. Add a new host with your server's Tailscale hostname
2. Set your username and password (or import your SSH key)
3. Enable the "Extra keys" toolbar for Ctrl, Tab, and arrow keys

Recommended Termius settings:
- **Font size:** 11-13pt (portrait), 12-14pt (landscape)
- **Terminal type:** `xterm-256color`
- **Scrollback:** 1000+ lines

Create Termius snippets for one-tap access:

| Snippet name | Command |
|---|---|
| ls | `dev ls` |
| hub | `dev hub` |
| attach | `dev attach` |
| menu | `dev m` |

### Mobile-Optimized Commands

- `dev m` — Quick numbered menu (easiest on a phone keyboard)
- `dev ls` — Adapts to narrow screens, shows compact cards
- `dev hub` — Full TUI, re-renders on terminal resize (rotating phone = instant re-layout)
- `dev attach` with no argument — Interactive numbered picker

Portrait mode gives ~40-50 characters wide. All compact layouts fit. Landscape mode gives ~80-100 characters — tables render normally.

---

## tmux Basics

Sessions persist after you disconnect. When you run `dev attach`, you're rejoining an existing tmux window.

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach (session keeps running) |
| `Ctrl+b s` | Switch between sessions |
| `Ctrl+b 1` / `2` / `3` | Switch between windows (agent / shell / server) |
| `Ctrl+b z` | Zoom pane (fullscreen toggle) |
| `Ctrl+b [` | Enter scroll mode (use arrow keys, `q` to exit) |
| `Ctrl+b \|` | Split pane vertically |
| `Ctrl+b -` | Split pane horizontally |
| `Alt+↑↓←→` | Move between panes |

---

## Partial Name Matching

You rarely need to type the full session name. Any unambiguous substring works:

```bash
dev attach feat     # matches "myproject-feat-auth"
dev kill welcome    # matches "myproject-welcome-screen"
dev logs task-57    # exact or partial both work
dev a price         # "a" is an alias for "attach"
```

If multiple sessions match, you'll get an interactive picker to choose from.

Common aliases:
- `d` — alias for `dev` (if configured in your shell)
- `dev a` — attach
- `dev k` — kill
- `dev n` — new

---

## Autonomous Agent Mode (yolo)

Use `--yolo` to let an agent work without asking for confirmation at each step:

```bash
dev new myproject feat/refactor --agent claude --yolo
```

The agent will work through the task autonomously. You can check in with:

```bash
dev logs feat        # see recent output
dev diff feat        # see what changed
dev attach feat      # join the session to review
```

Use `dev send` to give it additional instructions without attaching:

```bash
dev send feat "also update the tests"
```

---

## Telegram Notifications

Set up the Telegram bot to get notified when agents finish or need your input.

1. Message `@BotFather` on Telegram, create a new bot, copy the token
2. Get your chat ID by messaging the bot and checking `https://api.telegram.org/bot<token>/getUpdates`
3. Add to your account config:

```bash
dev setup-account   # includes Telegram setup step
```

Or set directly:

```json
// ~/.config/dev-cli/config.json
{
  "telegram_chat_id": "12345",
  "notify_on_complete": true
}
```

Then start the bot service:

```bash
dev bot start
dev services status  # verify it's running
```

---

## Multiple Projects on One VPS

The VPS supports multiple projects simultaneously. Each project has its own bare git repo and worktree directory:

```bash
dev init projecta
dev init projectb
dev projects         # list configured projects
```

Sessions from different projects share the same slot pool (50 slots total). Port assignments are project-agnostic — whatever's free gets assigned.

---

## SSH Key Setup

Skip password entry by setting up key-based auth:

```bash
# From your laptop
ssh-copy-id <username>@<server-hostname>
```

After this, `ssh <username>@<server>` connects without a password.
