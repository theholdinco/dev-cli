## How I use `dev` — my CLI for AI-powered development

I run a custom CLI called `dev` on a VPS (Hetzner, always on). I SSH into it from anywhere — laptop, phone (Termius), whatever — and manage AI coding agents (Claude Code, Codex) that work in parallel on my projects using git worktrees and tmux.

### The core flows

**1. Start a new feature**
```bash
dev new patagon welcome-screen --attach
```
This creates an isolated git worktree, allocates ports (frontend, backend, supabase), launches a tmux session with Claude Code, and drops me in. The AI already has the full codebase context. I describe what I want, it codes, I review. When done:
```bash
dev pr patagon-welcome-screen
```
Pushes the branch and creates a GitHub PR automatically.

**2. Quick question about the code**
```bash
dev ask patagon "where does the webauthn passkey domain come from?"
```
Spins up a temporary read-only worktree with Claude. No ports, no slot, no overhead. I get my answer and it cleans up after itself.

**3. Free-form AI session (no repo)**
```bash
dev ghost "what are the 10 most valuable things a 21yo founder can do?"
```
Opens Claude in a blank persistent directory. Good for brainstorming, scripting, data work — anything that isn't tied to a specific project.

**4. AI code review**
```bash
dev review https://github.com/org/repo/pull/27
```
Creates a session on the PR branch. Claude reads the diff, checks for issues, and can submit a review comment directly on GitHub.

**5. Queue tasks for async execution**
```bash
dev task add patagon "notify waitlist users when a deal goes active"
```
Adds a task to the queue. A background runner picks it up, creates a session, the AI works on it autonomously, creates a PR when done, and notifies me via Telegram. I can check on it anytime:
```bash
dev task ls
dev a task-42
```**6. Start from a specific branch**
```bash
dev new patagon mobile-improvements --from mobile --yolo --attach
```
`--from` lets me branch off something other than main. `--yolo` skips permission prompts so Claude works fully autonomously.

### Shortcuts & fuzzy matching

Most commands have short aliases and you almost never need to type the full session name — just enough to match:

```bash
dev a price        # attach to "patagon-price-changes" (fuzzy match)
dev a 57           # attach to "task-57"
dev a              # no argument = interactive picker
d a mobile         # "d" is an alias for "dev"
dev m              # mobile-friendly TUI menu (for phone SSH)
dev kill welcome   # kills "patagon-welcome-screen"
dev kill 57        # kills "task-57"
```

If multiple sessions match your search, it prompts you to pick one.

### Day-to-day management

```bash
dev ls              # see my active sessions
dev ls --all        # see everyone's sessions (multi-user VPS)
dev kill welcome    # stop agent, delete worktree, free ports
dev gc              # clean up dead sessions
dev diff task-57    # see what the AI changed
dev sync task-57    # rebase session on latest main
dev send task-57 "also add error handling for the edge case"
```
### The CLI builds itself

The `cli` repo is set up as a project in the VPS like any other. Whenever I want a new feature or fix, I just queue a task:

```bash
dev task add cli "when attaching with no params, only show my sessions by default"
dev task add cli "add a --from flag to select which branch to start from"
dev task add cli "telegram notifications aren't working, check the hooks config"
```

The task runner spins up a session, Claude reads the CLI codebase, implements the change, creates a PR, and notifies me. I review, merge, run `dev update`, and the new feature is live. The CLI is literally evolving itself through its own task system.

### Web dashboard

There's also a web UI (Flask + HTMX + Tailwind, dark theme) accessible from the browser via Tailscale. It gives me a visual overview of everything without needing to SSH in.

**What it shows:**
- **Sessions page** — all active sessions with live status (alive/dead), owner, project, branch, slot, age, assigned agents, and port allocations. Updates in real-time via Server-Sent Events every 3 seconds.
- **Tasks page** — the full task queue with color-coded statuses (pending/running/done/failed), linked sessions, and PR URLs once they're created.
- **Stats page** — server health: CPU, memory, disk usage, session counts, uptime.
- **Ports page** — port allocation table across all slots.
- **Doctor page** — system health diagnostics.

**What you can do from it:**
- Create new sessions (pick project, branch, agent, yolo mode)
- Kill or restart sessions
- Send prompts to running agents
- View live logs and diffs from a session
- Create PRs directly from the UI (regular or draft)
- Add and remove tasks
- Add or remove agents from a session

It's useful for quick monitoring from the phone browser or when I don't want to open a terminal, but for actual work I'm always in the CLI.

### Infrastructure that runs in the background

- **Web dashboard** — the Flask app described above
- **Telegram bot** — sends me notifications when agents finish or need my input
- **Task runner** — systemd service that auto-executes queued tasks

```bash
dev services status   # check web, bot, task-runner
dev doctor            # health check everything (gh, claude, tmux, etc.)
```

### How it works under the hood

Each session is a tmux window set with 2-3 panes: the AI agent, a shell in the worktree, and optionally a dev server. Port allocation uses a slot system (50 slots, each gets frontend + backend + supabase ports). State lives in JSON files (`ports.json`, `tasks.json`). The whole thing is ~2900 lines of bash.

Multi-user works via a shared port registry at `/etc/dev-cli/ports.json` — each session tracks its owner, so `dev ls` shows only your stuff by default.

### The mental model

Think of it as **tmux + git worktrees + AI agents + port management**, all unified under one command. I can have 5 features being worked on in parallel by different AI agents, each in its own isolated worktree with its own ports, and jump between them or let them run autonomously while I'm on my phone.
