# Security Model

dev-cli uses four layered security mechanisms to isolate users and protect the shared VPS.

## Overview

1. **Network layer** — Tailscale restricts who can reach the server at all
2. **Identity binding** — SSH is gated on Tailscale identity, not static keys
3. **Session/file permissions** — Linux user isolation keeps session data separate
4. **Port isolation** — authbind ensures users can only bind their own allocated ports

## Layer 1: Tailscale Network

The VPS firewall (UFW) allows only:
- SSH (port 22) from Tailscale interface
- Tailscale itself (UDP 41641)

All other inbound traffic is denied. Users must be on the tailnet before they can even attempt to connect.

Bootstrap sets up UFW with:

```
sudo ufw default deny incoming
sudo ufw allow in on tailscale0 to any port 22
sudo ufw allow 41641/udp
sudo ufw enable
```

## Layer 2: Tailscale Identity Binding

SSH is configured to authenticate users based on their live Tailscale identity rather than static SSH public keys.

**How it works:**

1. `dev admin add-user` records the user's Tailscale email in `/etc/dev-cli/users.json`
2. `sshd_config` is configured with `AuthorizedKeysCommand /opt/dev-cli/bin/validate-tailscale-identity.sh`
3. When a user connects, the validation script runs `tailscale whois` on the connecting IP
4. It compares the Tailscale-reported email against the registered email in `users.json`
5. If they match, SSH proceeds; if not, access is denied

This means:
- Revoking Tailscale access immediately blocks SSH, even without touching SSH keys
- Suspended users in `users.json` are rejected even with valid Tailscale credentials
- No SSH key management required

## Layer 3: Session and File Permissions

Each user is a separate Linux account. Their home directory, config, and worktrees are owned by their user. The shared port registry at `/etc/dev-cli/ports.json` uses group-based write access (`devs` group) with file locking for concurrent access.

Users cannot read each other's `~/.config/dev-cli/secrets.env` (chmod 600) or worktree contents.

## Layer 4: Port Isolation via authbind

Port ownership is enforced at the OS level using authbind:

- When a session is created (`dev new`), authbind rules are written granting that user permission to bind the allocated ports
- When a session is killed (`dev kill`), the authbind rules are removed
- Other users cannot bind those ports, even if they know the port numbers

Admins can grant temporary cross-user port access for debugging or pair programming:

```bash
dev admin port-access <username> --session <session> --grant
dev admin port-access <username> --session <session> --revoke
```

## Secrets Management

### Per-user secrets

Each user's secrets live at `~/.config/dev-cli/secrets.env` with permissions `chmod 600`. These are sourced by setup hooks when creating sessions. Users manage their own API keys here.

### Shared secrets

Shared secrets (e.g., team API keys) live at `/etc/dev-cli/secrets/` with `chmod 640` (root:devs). When a user is added, files here are symlinked into their config automatically.

To add a shared secret:

```bash
sudo nano /etc/dev-cli/secrets/myproject.env
sudo chmod 640 /etc/dev-cli/secrets/myproject.env
sudo chown root:devs /etc/dev-cli/secrets/myproject.env
```

## Audit Log

All admin actions and session lifecycle events are logged to `/etc/dev-cli/audit.log`.

Query the audit log:

```bash
# Recent events
dev admin audit --last 1h

# Events for a specific user
dev admin audit --user alice

# All session creation events
dev admin audit --event session-create

# Raw log
sudo cat /etc/dev-cli/audit.log
```

Log entries include: timestamp, acting user, target user (if applicable), event type, and relevant metadata (session name, ports, etc.).
