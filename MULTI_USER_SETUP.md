# Adding a New User

## Admin side

### 1. Create the user

```bash
sudo add-dev-user <username>
```

This creates the Linux user, installs dev-cli and Claude Code, sets up groups and PATH. Note the temporary password printed at the end.

### 2. Share credentials

Send the new user:
- Temporary password (they'll be forced to change it on first login)
- Server hostname: `ssh <username>@patagon`
- Tailscale invite link (they must join the tailnet to reach the server)

### 3. Verify (optional)

After they log in, check the shared registry:

```bash
cat /etc/dev-cli/ports.json   # their sessions should appear here
```

---

## User side

### 1. Join Tailscale

Install Tailscale and join the tailnet using the invite link from your admin. The server is only reachable through Tailscale.

### 2. First login

```bash
ssh <username>@patagon
```

You'll be prompted to change your password immediately.

### 3. Authenticate services

```bash
gh auth login       # GitHub — follow the prompts
claude login        # Claude Code — opens browser auth
```

### 4. Verify setup

```bash
dev doctor          # all tools should be green
```

### 5. Fix ports.json (if needed)

If `dev doctor` shows "ports.json — invalid JSON!", run:

```bash
echo '{}' > ~/.config/dev-cli/ports.json
```

### 6. Start working

```bash
dev init <project>              # set up a project (first time only)
dev new <project> <branch>      # create a session
dev ls                          # list your sessions
```

---

## Tips

- **SSH keys**: Set up key-based auth to skip password entry: `ssh-copy-id <username>@patagon`
- **tmux**: Sessions persist after disconnect. Reconnect with `dev attach <session>`
- **Shell customization**: Users can edit their own `~/.bashrc` freely — Homebrew and nvm are already sourced
- **Shared secrets**: API keys and env files are symlinked from `/etc/dev-cli/secrets/` into each user's config automatically

## Troubleshooting

| Problem | Fix |
|---|---|
| "Permission denied" on ports.json | User isn't in `devs` group. Run `sudo usermod -aG devs <user>`, then they re-login |
| `claude: command not found` | Re-run: `sudo su - <user> -c 'curl -fsSL https://claude.ai/install.sh \| bash'` |
| `dev: command not found` | Re-run: `sudo su - <user> -c "bash /opt/dev-cli/install.sh"` |
| flock errors on ports.json | Ensure `/etc/dev-cli` has group write: `sudo chmod g+ws /etc/dev-cli` |

## Removing a user

```bash
sudo su - <username> -c "dev kill --all"   # clean up their sessions
sudo userdel -r <username>                 # remove user and home dir
```
