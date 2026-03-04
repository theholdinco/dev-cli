# Devcontainers — Usage Guide

Devcontainers give each agent session its own isolated Docker environment. The agent runs inside the container with your credentials, SSH keys, and Git access forwarded in — so it can push branches and create PRs exactly like a local session, just fully sandboxed.

## Prerequisites

The `devcontainer` CLI must be installed on the VPS (it is included in `bootstrap.sh`):

```bash
npm install -g @devcontainers/cli
```

Docker must also be running. Verify both are present:

```bash
dev doctor
```

## Starting a container session

Add `--container` to `dev new`:

```bash
dev new myproject feat/my-feature --container
```

This generates a `devcontainer.json` in the worktree, starts the container (via `devcontainer up`), and drops you into a tmux session where the agent runs inside the container. The first startup takes longer because it pulls the Docker image and runs `postCreateCommand` (installs Claude Code, copies credentials, etc.). Subsequent starts reuse the cached image layer.

## Headless mode (recommended)

Headless mode is the primary use case for containers. Pass a prompt and the agent works autonomously — no interaction required:

```bash
dev new myproject feat/refactor --container --prompt "Refactor the API layer to use the repository pattern"
```

When a prompt is provided with `--container`, headless mode is enabled automatically. The agent runs `claude -p` (non-interactive), streams output to the tmux pane so you can watch, and drops into a shell when it finishes.

Attach to watch progress at any time:

```bash
dev attach myproject-feat-refactor
```

The tmux pane keeps the session open after the agent finishes — you can inspect the result before cleaning up.

## Passing secrets into the container

By default only API keys (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) are forwarded from `~/.config/dev-cli/secrets.env`. To forward the entire `secrets.env` file (e.g. for database URLs, third-party tokens):

```bash
dev new myproject fix/db-bug --container --env --prompt "Fix the connection pooling bug"
```

Only use `--env` when the agent actually needs those secrets. Omitting it keeps the container surface minimal.

## Interactive container sessions (experimental)

You can run a container session without a prompt for interactive use:

```bash
dev new myproject feat/explore --container
```

The tmux session opens with the agent running inside the container. This mode is functional but experimental — prefer headless for unattended tasks.

## Opening a shell inside the container

`dev shell` automatically detects container sessions and execs into the container instead of the host:

```bash
dev shell myproject-feat-refactor
```

This drops you into a bash shell inside the running container at the workspace directory, as the `node` user.

## Making containers the default for a project

Use `dev config` to set container mode (and optionally `--env`) as the default for a project so you don't have to pass flags every time:

```bash
dev config myproject
```

Select "use container" and optionally "pass secrets". After saving, `dev new myproject <branch>` will always use a container.

You can also configure the Claude model and effort level per project from the same prompt.

## Lifecycle

Container sessions behave like normal sessions for all management commands:

```bash
dev ls                          # shows container sessions alongside normal ones
dev attach myproject-feat-x     # attaches to tmux (agent runs inside container)
dev kill myproject-feat-x       # stops container, removes worktree, frees slot
dev gc                          # garbage-collects dead container sessions too
dev pr myproject-feat-x         # push + create PR (git runs inside container)
```

`dev kill` gracefully stops and removes the container before tearing down the tmux session and worktree.

## Choosing the right mode

| Scenario | Command |
|---|---|
| Fire-and-forget task | `--container --prompt "..."` |
| Task that needs DB/API secrets | `--container --env --prompt "..."` |
| Interactive agent in sandbox | `--container` (experimental) |
| Standard session (no isolation needed) | *(no flags)* |
