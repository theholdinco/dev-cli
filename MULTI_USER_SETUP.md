# Multi-User Setup Guide

## Pre-requisites (one-time, as your admin user)

### 1. Create shared infrastructure

```bash
sudo groupadd -f devs
sudo usermod -aG devs $USER
sudo mkdir -p /etc/dev-cli
sudo chown :devs /etc/dev-cli
sudo chmod g+ws /etc/dev-cli
echo '{}' | sudo tee /etc/dev-cli/ports.json > /dev/null
sudo chown :devs /etc/dev-cli/ports.json
sudo chmod g+w /etc/dev-cli/ports.json
```

> After adding yourself to `devs`, you need to re-login or run `newgrp devs` for it to take effect.

### 2. Re-install dev-cli

```bash
./install.sh
```

This will migrate any existing sessions from `~/.config/dev-cli/ports.json` into the global registry and rename the local file to `ports.json.migrated`.

### 3. Verify your sessions still work

```bash
dev ls          # should show your sessions (now user-prefixed)
dev ports       # should read from /etc/dev-cli/ports.json
```

> **Note:** Existing tmux sessions still use old names (without user prefix). You may need to `dev kill --all` and recreate them, or manually rename them.

## Adding a test user

```bash
sudo add-dev-user testuser
```

This will print a temporary password. The user must change it on first SSH login.

### Test as the new user

```bash
# From your admin session:
sudo su - testuser

# Or SSH in:
ssh testuser@localhost

# As testuser, verify:
dev doctor        # check dependencies
dev ls            # should see global sessions (empty for new user)
claude --version  # Claude Code should be installed
```

### Test session isolation

```bash
# As testuser:
dev new <project> main    # creates testuser-<project>-main

# As your admin user (in another terminal):
dev ls                    # should show both users' sessions
dev ls --mine             # should show only your sessions (if implemented)
```

Check `/etc/dev-cli/ports.json` — both users' sessions should be there with different slots and no port conflicts.

## Cleanup

```bash
# Kill test sessions
sudo su - testuser -c "dev kill --all"

# Remove test user
sudo userdel -r testuser
```

## Troubleshooting

- **"Permission denied" on ports.json** — User isn't in `devs` group. Run `sudo usermod -aG devs <user>` and have them re-login.
- **Old sessions not found** — Session names now include `$USER` prefix. Kill old sessions and recreate.
- **flock errors** — The lock file (`ports.json.lock`) needs to be writable in the same dir. If `/etc/dev-cli` has `g+ws`, this should work automatically.
