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
- Backward compatible: single-user mode (no Tailscale, no `users.json`) continues to work. The tool degrades gracefully when `/etc/dev-cli/users.json` does not exist.

---

## Existing Infrastructure (do not rebuild)

The codebase already has multi-user features that this design extends:

- **Session ownership:** `owner` field in `ports.json` (set to `$USER` on create).
- **Private sessions:** `--private` flag, `cmd_private` toggle, visibility filtering.
- **Visibility filtering:** `dev ls` shows own sessions; `--all` shows non-private + own private.
- **Owner checks:** Confirmation prompt before killing another user's session.
- **Port registry:** `/etc/dev-cli/ports.json` with `flock`-based file locking for concurrent access, `chmod 664` with `devs` group ownership.
- **User creation:** `add-dev-user` script in `bootstrap.sh`.
- **Doctor checks:** `cmd_doctor` verifies tools, Docker, GitHub auth, Tailscale.

This design builds on all of the above. Where something is "replaced," the old code is removed. Where something is "extended," existing behavior is preserved.

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
- `ports.json` stays at `/etc/dev-cli/ports.json` using the existing `flock`-based locking and `devs` group write permissions. No setgid helper needed — the current approach works.
- Private sessions: other users can't see the tmux window (enforced at tmux level, not just filtered from display).

### Port Isolation

The iptables `owner` module only works on OUTPUT, not INPUT — so it cannot prevent other users from connecting to your ports. Instead, use a socket-level approach:

- **Option A: `authbind`** — configure per-user port authorization. Each user's allocated ports are registered with authbind, and dev servers are launched through it.
- **Option B: Network namespaces** — each session runs in its own network namespace with only its allocated ports exposed. More isolated but more complex.
- **Option C: Loopback binding + Unix socket proxy** — dev servers bind to per-user Unix sockets (file permission enforced), with a lightweight proxy exposing them on TCP ports only to the owning user.

**Recommendation:** Start with Option A (authbind) for simplicity. It integrates cleanly with the existing session launch flow — wrap the dev server start command with `authbind`. Fall back to Option B if authbind proves too limited.

- Rules/config added on session create, removed on session kill.
- Admins can bypass for debugging (`dev admin port-access`).

### Secrets Isolation

- Per-user secrets at `~/.config/dev-cli/secrets.env` (chmod 600).
- Shared secrets provisioned by admins at `/etc/dev-cli/secrets/<key-name>` (chmod 640, group `devs`). During `add-user`, these are symlinked into the user's `~/.config/dev-cli/secrets/` directory as read-only.
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
dev admin set-limit <username> --max-sessions <N>
dev admin audit [--user <name>] [--last 24h]
dev admin status                        # system health: disk, ports, sessions, users
dev admin stale-sessions [--older-than 7d]
dev admin port-access <session> --grant <username>   # temporary cross-user access
dev admin backup [--output <path>]
dev admin restore <backup-path>
dev admin update
```

**Replaces:** The existing `add-dev-user` script in `bootstrap.sh`. That script is removed and its logic moves into `dev admin add-user`.

### User Registry (`/etc/dev-cli/users.json`)

```json
{
  "users": {
    "alice": {
      "tailscale_email": "alice@company.com",
      "role": "admin",
      "created": "2026-03-10T12:00:00Z",
      "status": "active",
      "max_sessions": 10,
      "onboarded": true
    },
    "bob": {
      "tailscale_email": "bob@company.com",
      "role": "user",
      "created": "2026-03-10T12:00:00Z",
      "status": "active",
      "max_sessions": 8,
      "onboarded": false
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
7. Symlink shared secrets from `/etc/dev-cli/secrets/` into user config.
8. Print onboarding instructions for the new user (copyable snippet to send them).

### `remove-user` Flow

- Kill all user's sessions, deallocate slots.
- `--purge` removes home directory and worktrees.
- Without `--purge`, disable login but preserve data.

### Audit Logging

- New logging facility added to `cmd_new`, `cmd_kill`, `cmd_attach`, and all `dev admin` commands.
- Log to `/etc/dev-cli/audit.log` in structured JSON-lines format:
  ```json
  {"ts":"2026-03-10T12:00:00Z","actor":"alice","action":"session.create","target":"my-feature","details":{}}
  {"ts":"2026-03-10T12:01:00Z","actor":"bob","action":"session.kill","target":"old-branch","details":{"owner":"bob"}}
  {"ts":"2026-03-10T12:02:00Z","actor":"alice","action":"admin.suspend-user","target":"charlie","details":{}}
  ```
- `dev admin audit` reads and filters the log by user, action type, and time range.
- File is append-only, group-writable by `devs`.

### Role Enforcement

Every `dev admin` command checks `users.json` for the caller's role before executing. Users without admin role get a clear error message.

---

## Workstream 3: User Onboarding

### `dev setup-account`

New command that wraps the existing `dev doctor` checks with an interactive first-time flow. It does NOT replace `dev setup` (project setup) or `dev doctor` (health check) — it orchestrates them for first login.

1. Tailscale verification — confirm identity matches admin registration in `users.json`.
2. GitHub auth — check if `gh auth status` passes; if not, walk through `gh auth login`.
3. Claude auth — check if `claude` is authenticated; if not, walk through `claude login`.
4. Run `dev doctor` — verify all dependencies.
5. Mark user as `"onboarded": true` in `users.json`.
6. Print quick-start guide: "Run `dev init <project>` to get started."

### `dev doctor` Improvements

Extend the existing `cmd_doctor` with:

- Check user's registration status in `users.json`.
- Check port isolation config (authbind) is in place for user.
- Check user's role and permissions.
- Ensure all checks have color-coded pass/fail output with fix instructions (some already do).

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
- Consolidate into new structure then remove: `MULTI_USER_SETUP.md`, `HOW_I_USE_IT.md`, `docs/TEAM_SETUP.md`, `docs/MOBILE_SETUP.md`.

### Principles

- Admin docs: concise, assume DevOps competence.
- User docs: hand-holding, include examples of expected output.

---

## Workstream 5: Resource Management

### Session Limits

- Per-user session cap stored in `users.json` as `max_sessions` (default 8).
- `dev admin set-limit <username> --max-sessions N` updates the field.
- Enforced in `cmd_new`: count user's active sessions in `ports.json`, reject if at limit.

### Stale Session Cleanup

- Idle detection via tmux: check `tmux display-message -p -t <session> '#{window_activity}'` for last activity timestamp.
- `dev admin stale-sessions [--older-than 7d]` lists sessions with no tmux activity past the threshold.
- Optional auto-cleanup: admin sets policy in `/etc/dev-cli/config.json` (`"stale_cleanup_days": 14`), enforced by a cron job or systemd timer.

### Disk Monitoring

- Per-user disk usage (sum of worktree sizes) surfaced in `dev admin status`.
- Warning threshold configurable in `/etc/dev-cli/config.json`.

---

## Workstream 6: Operations

### Backup & Restore

- `dev admin backup [--output <path>]` — exports `users.json`, `ports.json`, project configs, hooks, templates, audit log into a timestamped tarball.
- `dev admin restore <backup-path>` — restores config state (not worktrees — those come from git).
- Useful for VPS migration.

### Update Mechanism

- `dev admin update` — pulls latest release from GitHub (tagged releases), reinstalls binaries for all users by copying to each user's `~/.local/bin/`.
- Extends existing `cmd_update` (which updates for the current user only). `dev admin update` is the multi-user variant.
- Active sessions are not interrupted — they continue with the old binary until next launch.
- Version tracked in `/etc/dev-cli/version` and per-user at `~/.local/bin/.dev-version`.

---

## Dependency Graph

```
Security Model ←→ Admin CLI (coupled, design together)
       ↓
User Onboarding (depends on admin CLI)

Documentation (fully parallel, independent)
Resource Management (independent, but uses users.json from Admin CLI)
Operations (depends on Admin CLI for command structure and role checks)
```

**Parallelizable for agents:**
- Agent 1: Security + Admin CLI (core, must go first)
- Agent 2: Documentation (fully independent)
- Agent 3: Resource Management (can start once users.json schema is defined)
- Agent 4: Operations (can start once admin CLI structure exists)
- Agent 5: User Onboarding (starts after Admin CLI is functional)

## Out of Scope

- Web dashboard authentication (Tailscale is the perimeter)
- Per-session CPU/memory limits
- Built-in billing/metering
- Plugin system
- Project-level access control (git handles this)
- Licensing/feature gating
