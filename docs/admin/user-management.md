# User Management

Managing users on a shared dev-cli VPS.

## Adding Users

```bash
dev admin add-user <username> --tailscale-email <email> [--role admin|user]
```

This command:
1. Creates a Linux system user
2. Installs dev-cli under the new user's account
3. Binds their Tailscale identity (email → SSH authorized keys)
4. Symlinks shared secrets from `/etc/dev-cli/secrets/` into their config
5. Prints onboarding instructions you can send to the user

**Examples:**

```bash
dev admin add-user alice --tailscale-email alice@company.com --role user
dev admin add-user bob --tailscale-email bob@company.com --role admin
```

The printed onboarding message includes the server hostname, Tailscale instructions, and first-login steps.

## Listing Users

```bash
dev admin list-users
```

Shows a table with each user's role, status (active/suspended), number of active sessions, and account creation date.

## Suspending Users

```bash
dev admin suspend-user <username>
```

Disables the user's login without deleting any of their data or sessions. Their sessions will continue running (unless you kill them explicitly), but they cannot SSH in until restored.

Useful for temporary access removal or offboarding while preserving work.

## Restoring Users

```bash
dev admin restore-user <username>
```

Re-enables SSH access for a suspended user. Their existing sessions and config are intact.

## Removing Users

```bash
# Soft remove: disables login, keeps home directory
dev admin remove-user <username>

# Hard remove: deletes home directory and all data
dev admin remove-user <username> --purge
```

Before removing, kill their active sessions to free up slots and ports:

```bash
dev admin kill-sessions <username>
dev admin remove-user <username> --purge
```

## Roles

There are two roles: `admin` and `user`.

| Capability | user | admin |
|---|---|---|
| Create/kill own sessions | yes | yes |
| View all users' sessions (`dev ls --all`) | no | yes |
| Kill other users' sessions | no | yes (with confirmation) |
| Run `dev admin` subcommands | no | yes |
| Access audit log | no | yes |

### Changing a User's Role

```bash
dev admin set-role <username> admin
dev admin set-role <username> user
```

## Session Limits

Each user has a maximum number of concurrent sessions. The default is 8. Admins can adjust this per user:

```bash
dev admin set-limit <username> --max-sessions 10
```

To check a user's current limit and usage:

```bash
dev admin list-users   # shows session count
dev admin status       # overall server state
```

If a user hits their limit, they'll see an error when running `dev new`. They can either kill old sessions (`dev kill <session>`) or ask an admin to raise their limit.
