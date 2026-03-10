# dev-cli Productization Design

## Goal

Transform dev-cli from an internal tool into a self-hosted product for dev teams and agencies. A team lead deploys it on a VPS, onboards developers, and the system enforces security boundaries structurally.

## Target Audience

- **Admins:** DevOps-comfortable. Know SSH, Linux, git, tmux.
- **Users:** May be junior devs. Need clear guidance to connect and start working.

## Design Philosophy

- CLI-first (no web admin panel)
- Security is structural, not trust-based
- Tailscale identity is the source of truth
- Parallel workstreams for agent-driven implementation

---

## Workstream 1: Security Model

### Identity Binding

- During `dev admin add-user`, the admin associates a Tailscale identity (email) with a Linux user.
- Mapping stored in `/etc/dev-cli/users.json`.
- SSH `AuthorizedKeysCommand` hook validates on login: if the Tailscale node's owner doesn't match the Linux user's bound identity, the connection is rejected.
- Users cannot `su` or `ssh localhost` to other users — disable password auth for local connections, remove users from `sudo` group.

### Roles

- Two roles: `admin` and `user`.
- Admins: can run `dev admin *` commands, see all sessions, kill any session, manage users.
- Users: can only manage their own sessions, see non-private sessions (read-only), no system-level access.
- Role stored in `/etc/dev-cli/users.json`.

### Session Enforcement

- Worktree directories owned by the creating user (file permissions).
- `ports.json` at `/etc/dev-cli/ports.json` with a setgid helper for atomic writes — users can read, writes go through a controlled path.
- Private sessions: other users can't see the tmux window (enforced at tmux level, not just filtered from display).

### Port Isolation

- When a slot is allocated, iptables `owner` match rules ensure only the session owner's UID can bind to those ports.
- Other users on the box cannot connect to dev server ports even if they know the port number.
- Rules added on session create, removed on session kill.
- Admins can bypass for debugging (`dev admin port-access`).

### Secrets Isolation

- Per-user secrets at `~/.config/dev-cli/secrets.env` (chmod 600).
- Shared secrets at `/etc/dev-cli/secrets/` are read-only symlinks.
- API keys (Claude, GitHub) are strictly per-user, never shared.

---

## Workstream 2: Admin CLI

### Commands

```
dev admin add-user <username> --tailscale-email <email> [--role admin|user]
dev admin remove-user <username> [--purge]
dev admin list-users
dev admin suspend-user <username>       # disable login, keep data
dev admin restore-user <username>
dev admin set-role <username> <role>
dev admin audit [--user <name>] [--last 24h]
dev admin status                        # system health: disk, ports, sessions, users
dev admin port-access <session> --grant <username>   # temporary cross-user access
```

### User Registry (`/etc/dev-cli/users.json`)

```json
{
  "users": {
    "alice": {
      "tailscale_email": "alice@company.com",
      "role": "admin",
      "created": "2026-03-10T...",
      "status": "active"
    },
    "bob": {
      "tailscale_email": "bob@company.com",
      "role": "user",
      "created": "2026-03-10T...",
      "status": "active"
    }
  }
}
```

### `add-user` Flow

1. Validate Tailscale email is in the tailnet (via `tailscale status`).
2. Create Linux user, add to `devs` group (not `sudo` unless role=admin).
3. Install dev-cli binaries to user's `~/.local/bin`.
4. Install Claude Code.
5. Bind Tailscale identity in `users.json`.
6. Set up SSH enforcement (only this Tailscale identity can log in as this user).
7. Print onboarding instructions for the new user.

### `remove-user` Flow

- Kill all user's sessions, deallocate slots.
- `--purge` removes home directory and worktrees.
- Without `--purge`, disable login but preserve data.

### Audit Logging

- All `dev admin` commands log to `/etc/dev-cli/audit.log`.
- All session lifecycle events (create, kill, attach) log with timestamp + actor.
- `dev admin audit` reads and filters the log.

---

## Workstream 3: User Onboarding

### `dev setup-account`

Interactive command for first-time users:

1. Tailscale verification — confirm identity matches admin registration.
2. GitHub auth — walk through `gh auth login`.
3. Claude auth — walk through `claude login`.
4. SSH key setup (if needed for GitHub).
5. `dev doctor` — verify everything works.
6. Mark user as "onboarded" in `users.json`.

### `dev doctor` Improvements

- Check user's auth status (GitHub, Claude, Tailscale).
- Check port isolation rules are in place.
- Check user's role and permissions.
- Color-coded pass/fail output with fix instructions.

### Goal

New user goes from "admin gave me credentials" to "running first session" in under 5 minutes.

---

## Workstream 4: Documentation

### Admin Guide (`docs/admin/`)

- `quickstart.md` — VPS setup in 10 minutes (bootstrap + first user).
- `user-management.md` — add/remove/suspend users, roles.
- `security.md` — how identity binding works, port isolation, audit logs.
- `troubleshooting.md` — common issues, recovery procedures.
- `configuration.md` — hooks, templates, shared secrets, project setup.

### User Guide (`docs/user/`)

- `getting-started.md` — connect, run `dev setup-account`, create first session.
- `daily-workflow.md` — common commands, hub usage, attaching/detaching.
- `commands.md` — full command reference with examples.
- `tips.md` — mobile access, tmux shortcuts, Telegram notifications.
- `faq.md`

### Migration

- Current `README.md` becomes a landing page pointing to both tracks.
- `MULTI_USER_SETUP.md`, `HOW_I_USE_IT.md`, `docs/TEAM_SETUP.md` consolidated into new structure, then removed.

### Principles

- Admin docs: concise, assume DevOps competence.
- User docs: hand-holding, include examples of expected output.

---

## Workstream 5: Resource Management

### Session Limits

- Per-user session cap (configurable by admin, default 8).
- `dev admin set-limit <username> --max-sessions N`.
- Enforced at session creation time.

### Stale Session Cleanup

- Sessions idle for X days get flagged.
- `dev admin stale-sessions` lists them.
- Optional auto-cleanup policy (admin-configurable).

### Disk Monitoring

- Disk usage warnings per user (worktrees can grow large).
- Surfaced in `dev admin status`.

---

## Workstream 6: Operations

### Backup & Restore

- `dev admin backup` — exports `users.json`, `ports.json`, project configs, hooks.
- `dev admin restore <backup>` — restores config state (not worktrees).
- Useful for VPS migration.

### Update Mechanism

- `dev admin update` — pulls latest release, reinstalls binaries for all users.
- Version tracking per user.

---

## Dependency Graph

```
Security Model ←→ Admin CLI (coupled, design together)
       ↓
User Onboarding (depends on admin CLI)

Documentation (fully parallel, independent)
Resource Management (independent)
Operations (independent)
```

## Out of Scope

- Web dashboard authentication (Tailscale is the perimeter)
- Per-session CPU/memory limits
- Built-in billing/metering
- Plugin system
- Project-level access control (git handles this)
- Licensing/feature gating
