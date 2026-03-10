# Commands Reference

Full reference for all `dev` commands.

## Session Management

### `dev new <project> <branch> [options]`

Create a new worktree session with an optional AI agent.

```bash
dev new myproject feat/auth --agent claude
dev new myproject fix/bug --agent codex
dev new myproject experiment          # no agent, just a worktree
dev new myproject feat/x --from staging --agent claude  # branch from staging
dev new myproject feat/x --agent claude --yolo          # autonomous mode
dev new myproject feat/x --agent claude --attach        # attach immediately after create
```

Options:
- `--agent claude|codex|none` — which AI agent to launch (default: none)
- `--from <branch>` — branch off this branch instead of main
- `--yolo` — skip agent confirmation prompts (autonomous mode)
- `--attach` — attach to the session immediately after creation

### `dev kill <session>`

Stop agent, remove worktree, free ports.

```bash
dev kill myproject-feat-auth
dev kill feat          # partial match
dev kill --all         # kill all your sessions
```

### `dev attach [session]`

Attach to a running session's tmux window.

```bash
dev attach myproject-feat-auth
dev attach feat        # partial match
dev attach             # interactive picker
```

### `dev ls [options]`

List active sessions.

```bash
dev ls                 # your sessions
dev ls --all           # all users' sessions
```

### `dev hub`

Open the interactive TUI dashboard. Shows all sessions with live preview pane and keyboard shortcuts.

### `dev rename <session> <new-name>`

Rename an existing session.

---

## Project Management

### `dev init [project]`

Interactive project setup. Prompts for git URL, configures worktree paths, and generates a setup hook or env template.

### `dev setup <project> <git-url>`

Quick non-interactive setup. Bare-clones the repo and creates a minimal project config.

```bash
dev setup myproject git@github.com:org/myproject.git
```

### `dev clone <project>`

Clone a configured project's worktrees directory to a new path.

### `dev projects`

List all configured projects.

### `dev template <project>`

Open the project's env template or setup hook in `$EDITOR`.

---

## Git and PR

### `dev pr <session> [options]`

Push the branch and create a GitHub PR.

```bash
dev pr feat-auth
dev pr feat-auth --draft      # draft PR
dev pr feat-auth --kill       # kill session after PR created
```

### `dev sync <session>`

Rebase the session's branch on the latest `main`.

```bash
dev sync feat-auth
```

### `dev diff <session>`

Show uncommitted changes in the worktree.

### `dev branch <session>`

Print the branch name for a session.

---

## Monitoring

### `dev status [session]`

Show detailed status for a session, including ports, agent PID, worktree path, and uptime.

```bash
dev status feat-auth
```

### `dev doctor`

Health check all dependencies (tmux, jq, gh, claude, docker, tailscale, etc.). Prints a checklist with pass/fail for each.

### `dev logs <session>`

Show recent output from a session's agent.

```bash
dev logs feat-auth
dev logs feat-auth --lines 100
```

### `dev ports`

Show the full port allocation table across all slots.

### `dev url <session>`

Print the Tailscale URL for a session's frontend port.

---

## Admin

Requires admin role. See [User Management](../admin/user-management.md) and [Security](../admin/security.md) for details.

### `dev admin add-user <username> --tailscale-email <email> [--role admin|user]`

Add a new user to the server.

### `dev admin list-users`

Show all users with role, status, session count, and creation date.

### `dev admin suspend-user <username>`

Disable login for a user without deleting data.

### `dev admin restore-user <username>`

Re-enable login for a suspended user.

### `dev admin remove-user <username> [--purge]`

Remove a user. `--purge` also deletes home directory.

### `dev admin set-role <username> admin|user`

Change a user's role.

### `dev admin set-limit <username> --max-sessions <n>`

Set the maximum concurrent sessions for a user.

### `dev admin kill-sessions <username>`

Kill all sessions belonging to a user.

### `dev admin stale-sessions [--older-than <duration>] [--kill]`

List or kill sessions that have been idle.

```bash
dev admin stale-sessions --older-than 7d
dev admin stale-sessions --older-than 7d --kill
```

### `dev admin audit [options]`

Query the audit log.

```bash
dev admin audit --last 1h
dev admin audit --user alice
dev admin audit --since "2024-01-15 09:00"
```

### `dev admin status`

Overall server status: users, sessions, slots used, disk, memory.

### `dev admin update`

Update dev-cli to the latest version on the server.

### `dev admin backup` / `dev admin restore`

Backup or restore the ports registry and config.

---

## Other

### `dev setup-account`

Interactive first-time account setup. Authenticates GitHub, Claude Code, and runs `dev doctor`.

### `dev send <session> <message>`

Send a message to a running agent without attaching.

```bash
dev send feat-auth "also handle the edge case where the token is expired"
```

### `dev gc`

Garbage-collect dead sessions (sessions in the registry whose tmux windows no longer exist).

### `dev shell <session>`

Open a shell in the session's worktree directory.

### `dev worktree <project> <branch>`

Create a worktree without launching an agent.

### `dev services status`

Check status of background services (web dashboard, Telegram bot, task runner).

### `dev --version`

Print the installed dev-cli version.
