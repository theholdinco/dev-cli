# Mobile Setup Guide

Using dev-cli from a phone via SSH (Termius, Blink, etc.).

## Termius Settings

- **Font size:** 11-13pt works well in portrait
- **Terminal type:** `xterm-256color`
- **Keyboard:** Enable "Extra keys" toolbar for Ctrl, arrow keys, Tab
- **Scrollback:** 1000+ lines

## Snippets to Add

Create these as Termius snippets for one-tap access:

| Name    | Command         |
|---------|-----------------|
| **ls**  | `dev ls`        |
| **hub** | `dev hub`       |
| **mob** | `dev m`         |
| **att** | `dev attach`    |
| **st**  | `dev stats`     |

## Workflow

### From terminal (SSH)
- `dev m` — Quick menu with numbered choices (easiest on phone)
- `dev ls` — Auto-adapts to narrow screens, shows compact cards
- `dev hub` — Full TUI, also adapts to width
- `dev stats` — Text-based overview on narrow terminals, btop on wide

### From web/Telegram (no SSH needed)
- **Web dashboard** (`dev web start`) — Session list, create/kill from browser
- **Telegram bot** (`dev bot start`) — `/ls`, `/new`, `/kill` from chat

## Tips

- Portrait mode gives ~40-50 chars wide — all compact layouts fit
- Landscape gives ~80-100 chars — tables render normally
- `dev attach` with no args gives a numbered picker (easy on phone)
- Use `Ctrl+a d` to detach from tmux sessions
- The hub re-renders on terminal resize (rotate phone = instant re-layout)
