# Troubleshooting

Common problems and how to resolve them.

## User Can't Log In

**Symptoms:** SSH connection refused or "Permission denied".

**Check Tailscale:**
```bash
# On the user's machine
tailscale status
```
They must be connected to the tailnet and the VPS must appear as reachable.

**Check user status:**
```bash
dev admin list-users
```
Look for `suspended` status. If suspended, restore them:
```bash
dev admin restore-user <username>
```

**Check SSH configuration:**
```bash
sudo sshd -T | grep AuthorizedKeysCommand
```
Should show `/opt/dev-cli/bin/validate-tailscale-identity.sh`. If blank or wrong, re-run bootstrap.

**Verify Tailscale identity binding:**
```bash
sudo /opt/dev-cli/bin/validate-tailscale-identity.sh <username>
```
This simulates what sshd runs. It should print a public key if identity matches.

---

## Session Creation Fails

**Symptoms:** `dev new` errors out immediately.

**Slot exhaustion (50 slots total):**
```bash
dev ls --all   # see all sessions across all users
```
If slots 1-50 are all occupied, someone needs to kill sessions. Admins can force-kill:
```bash
dev admin kill-sessions <username>
```

**User hit session limit:**
```bash
dev admin list-users   # check session count vs limit
dev admin set-limit <username> --max-sessions 10
```

**Orphaned sessions (sessions in registry but tmux is dead):**
```bash
dev ls --all          # look for sessions with dead status
dev gc                # garbage-collect dead sessions
```

---

## Port Conflicts

**Symptoms:** Dev server fails to start, "address already in use" errors in logs.

**Check what's using the port:**
```bash
ss -tlnp | grep 3001
```

**Find the owning session:**
```bash
dev ls --all | grep 3001
```

**Kill the conflicting session:**
```bash
dev kill <session>
```

If the session is already dead but ports weren't freed, kill the process manually and clean the registry:
```bash
kill $(ss -tlnp | grep 3001 | awk '{print $6}' | grep -oP 'pid=\K[0-9]+')
dev gc   # clean up dead registry entries
```

---

## ports.json Corruption

**Symptoms:** `dev doctor` reports "ports.json — invalid JSON!", all commands fail.

**Backup location:**
The shared registry is backed up periodically to `/etc/dev-cli/backups/`. Check for recent backups:
```bash
ls -lt /etc/dev-cli/backups/
```

**Restore from backup:**
```bash
dev admin restore --from /etc/dev-cli/backups/ports-2024-01-15.json
```

**Manual reset (if no valid backup):**
```bash
# For per-user registry
echo '{}' > ~/.config/dev-cli/ports.json

# For shared registry (admin only)
sudo sh -c 'echo "{}" > /etc/dev-cli/ports.json'
sudo chmod 664 /etc/dev-cli/ports.json
sudo chown root:devs /etc/dev-cli/ports.json
```

After a manual reset, any sessions that were actually running are now "orphaned" (running but not in the registry). Identify and kill them:
```bash
tmux ls   # list all tmux sessions still alive
```

---

## Viewing Audit Logs for Debugging

```bash
# Last hour of events
dev admin audit --last 1h

# Events for a specific user
dev admin audit --user alice

# Since a specific time
dev admin audit --since "2024-01-15 09:00"

# Raw log (requires sudo)
sudo tail -100 /etc/dev-cli/audit.log
```

---

## Stale Sessions

**Symptoms:** Sessions that haven't had activity in days, wasting slots and ports.

**Find stale sessions:**
```bash
dev admin stale-sessions --older-than 7d
```

**Review and kill them:**
```bash
dev admin stale-sessions --older-than 7d --kill
```

Or notify the user first and let them decide:
```bash
dev admin stale-sessions --older-than 3d   # shows owner, age, last activity
```

---

## Other Common Fixes

| Problem | Fix |
|---|---|
| "Permission denied" on ports.json | User isn't in `devs` group: `sudo usermod -aG devs <user>`, user re-logs in |
| `claude: command not found` | Re-install: `sudo su - <user> -c 'curl -fsSL https://claude.ai/install.sh \| bash'` |
| `dev: command not found` | Re-install: `sudo su - <user> -c "bash /opt/dev-cli/install.sh"` |
| flock errors on ports.json | Fix group write: `sudo chmod g+ws /etc/dev-cli` |
| Authbind rules not applied | Restart session creation: kill and re-run `dev new` |
