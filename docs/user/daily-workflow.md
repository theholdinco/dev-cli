# Daily Workflow

Common patterns for working with dev-cli day to day.

## Starting a Session

```bash
dev new <project> <branch> --agent claude
```

This creates a git worktree on the specified branch, allocates dedicated ports, generates `.env` files via the project's setup hook, and launches Claude Code in a persistent tmux session.

To start without an agent (just a worktree + shell):

```bash
dev new <project> <branch>
```

To branch off something other than `main`:

```bash
dev new <project> feat/my-feature --from staging --agent claude
```

## Attaching to a Session

```bash
dev attach <session>
```

Partial name matching works — you don't need the full session name:

```bash
dev attach feat     # matches "myproject-feat-auth" if unique
dev attach          # no argument opens an interactive picker
```

The session is a tmux window. Press `Ctrl+b d` to detach without stopping it.

## Checking Status

```bash
dev ls              # your sessions
dev ls --all        # all users' sessions (if admin)
```

Output shows session name, agent type, assigned ports, and age.

## Using the Dashboard

```bash
dev hub
```

The TUI dashboard shows all your sessions with a live preview pane. Keyboard shortcuts:

| Key | Action |
|-----|--------|
| `1`-`9` | Select session |
| `Enter` | Attach to selected session |
| `n` | New session |
| `k` | Kill selected session |
| `p` | Show ports |
| `m` | Create PR |
| `l` | Open lazygit |
| `s` | Open shell in worktree |
| `u` | Show URL |
| `a` | Toggle all users / your sessions |
| `r` | Refresh |
| `q` | Quit |

## Killing Sessions

```bash
dev kill <session>
```

This stops the agent, removes the git worktree, and frees the allocated ports. Partial name matching applies:

```bash
dev kill feat       # kills "myproject-feat-auth"
```

## Working with Multiple Branches

Each `dev new` call creates an isolated worktree. You can have many running simultaneously:

```bash
dev new myproject feat/login --agent claude
dev new myproject fix/api-bug --agent claude
dev new myproject refactor/db --agent codex
dev ls
```

Each session has its own ports, its own `.env` files, and its own git state. Changes in one session don't affect others.

## PR Workflow

```bash
dev pr <session>
```

This pushes the branch and creates a GitHub PR. Options:

```bash
dev pr feat --draft          # create as draft
dev pr feat --kill           # auto-kill session after PR created
dev pr feat --draft --kill   # both
```

## Sending Messages to Agents

While an agent session is running, you can send it additional instructions without attaching:

```bash
dev send <session> "also add error handling for the edge case"
```

## Running Agents Autonomously

For hands-off work, use `--yolo` mode which skips Claude's confirmation prompts:

```bash
dev new myproject feat/big-refactor --agent claude --yolo
```

The agent will work through the task without asking for approval at each step. Check in periodically with `dev attach` or review the output with `dev logs <session>`.

## Checking Diffs and Logs

```bash
dev diff <session>    # see what the agent has changed
dev logs <session>    # recent agent output
```

## Syncing with Latest Main

If `main` has advanced while your session was running:

```bash
dev sync <session>    # rebase session branch on latest main
```

## Cleaning Up Dead Sessions

```bash
dev gc    # remove sessions whose tmux windows no longer exist
```
