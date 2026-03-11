# FAQ

## How do I see other people's sessions?

If you're an admin:

```bash
dev ls --all
```

If you're a regular user, you can only see your own sessions by default. Ask an admin to check on other sessions.

From the hub (`dev hub`), press `a` to toggle between "your sessions" and "all sessions" (admins only).

---

## What ports does my session use?

```bash
dev status <session>
```

This shows frontend, backend, and Supabase ports for the session. You can also see all port assignments:

```bash
dev ports
```

Access your session from any Tailscale device at `http://<tailscale-ip>:<frontend-port>`.

---

## How do I share a session with someone?

**Same user account:** If someone else has SSH access as you, they can run `dev attach <session>` to join the same tmux window — you'll both see the same terminal.

**Different user:** Ask an admin to use `dev admin port-access` to grant temporary access to your session's ports. They can then view your running app in their browser via the Tailscale IP.

For collaborative code review, the most practical option is to push the branch (`dev pr <session> --draft`) and review via GitHub.

---

## My session is stuck / agent is frozen

First, check what's happening:

```bash
dev attach <session>
```

If the agent is hanging on a prompt, you can type a response. If it's truly stuck:

1. Detach from the session: `Ctrl+b d`
2. Kill and restart: `dev kill <session>` then `dev new <project> <branch>`

To preserve agent context before killing, look at `dev diff <session>` to see what was changed, and `dev logs <session>` for recent output.

---

## I hit my session limit

```bash
dev ls   # check which sessions you have
```

Kill sessions you're done with:

```bash
dev kill <old-session>
```

If you need more than your current limit, ask an admin:

```bash
# Admin runs:
dev admin set-limit <username> --max-sessions 12
```

---

## How do I update dev-cli?

Ask an admin:

```bash
# Admin runs:
dev admin update
```

This pulls the latest version and reinstalls for all users. Your sessions and config are unaffected.

---

## How do I set up a new project?

```bash
dev init <project-name>
```

This runs an interactive setup wizard that:
1. Asks for the git repository URL
2. Bare-clones it into `~/projects/<project>/`
3. Creates a setup hook or env template (your choice)
4. Optionally runs a health check

For a quick non-interactive setup:

```bash
dev setup myproject git@github.com:org/myproject.git
```

---

## How do I run two agents on the same feature?

Create two sessions on the same branch:

```bash
dev new myproject feat/big-task --agent claude
dev new myproject feat/big-task-b --agent codex
```

Each session gets its own worktree and ports. They both start from the same branch but are isolated — changes in one don't affect the other. You'd merge the work manually or via PRs.

---

## My worktree has merge conflicts

```bash
dev attach <session>
# Inside the session:
git status
git mergetool   # or resolve manually
```

Or rebase on the latest main:

```bash
dev sync <session>
```

---

## Can I access the server from my phone browser?

Yes, via the web dashboard. If your admin has started it:

```bash
dev services status   # check if web dashboard is running
```

Then open `http://<tailscale-ip>:<web-port>` in your phone browser (while on Tailscale). The web dashboard shows sessions, lets you create and kill them, and displays live logs.
