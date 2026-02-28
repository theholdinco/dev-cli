# Devcontainers — How It Works

This document explains the internal mechanics of container sessions in dev-cli. Read this if you are debugging container behaviour, extending the feature, or want to understand what happens under the hood.

## Overview

When `--container` is passed to `dev new`, three things happen before the tmux session is created:

1. A `devcontainer.json` is generated (or the project's existing one is used).
2. The container is started via the `devcontainer` CLI.
3. The container ID is stored in the port registry so all subsequent commands (`attach`, `shell`, `kill`, etc.) can target it.

All agent commands then run via `docker exec` rather than directly on the host.

## Step 1 — Generating `devcontainer.json`

`ensure_devcontainer_json()` in `bin/dev` generates `.devcontainer/devcontainer.json` inside the worktree. If the project repo already ships a `devcontainer.json` (at `.devcontainer/devcontainer.json` or `.devcontainer.json`), that file is used as-is and generation is skipped.

### Image selection

The generated config uses the Microsoft JavaScript/Node devcontainer image:

```
mcr.microsoft.com/devcontainers/javascript-node:<version>
```

The Node version is detected from the project's `.nvmrc` or `.node-version` file. If neither exists, it defaults to `22`.

### `containerEnv` — always-present environment variables

These variables are baked into `containerEnv` so they are available to every process in the container, including to `docker exec` calls that do not inherit the host shell environment:

| Variable | Source |
|---|---|
| `DEV_PROJECT` | session project name |
| `DEV_BRANCH` | session branch name |
| `CLAUDE_CODE_EFFORT_LEVEL` | project config or `"high"` |
| `DISABLE_AUTOUPDATER` | hardcoded `"1"` |
| `ANTHROPIC_MODEL` | project config (omitted if unset) |
| `DEV_FRONTEND_PORT` / `DEV_BACKEND_PORT` | slot allocation (omitted if project has neither) |
| `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | read from `~/.config/dev-cli/secrets.env` |

API keys are sourced from `secrets.env` at generation time and written directly into the JSON. The set of key names is defined by `CONTAINER_API_KEYS` at the top of `bin/dev`.

### `remoteEnv` — optional full secrets passthrough (`--env`)

When `--env` is used, the non-API-key entries from `secrets.env` are also passed as `remoteEnv` with `${localEnv:KEY}` references. The `devcontainer` CLI resolves these from the host environment at startup.

### Mounts

Four bind mounts are always added:

| Host path | Container path | Mode |
|---|---|---|
| `~/.ssh` | `/tmp/.host-ssh` | read-only |
| `~/.gitconfig` | `/tmp/.host-gitconfig` | read-only |
| `~/.claude` (if present) | `/tmp/.host-claude` | read-only |
| `~/.config/gh` (if present) | `/tmp/.host-gh` | read-only |
| `~/projects/<project>` (bare repo) | `/tmp/.bare-repo` | read-write |

The bare repo mount is read-write because the agent needs to commit and push from inside the container.

### Preventing accidental commits of generated config

The generated `.devcontainer/` directory is added to `.git/info/exclude` (the worktree-local gitignore) so it never appears as an untracked file and cannot be accidentally committed to the project repo.

## Step 2 — `postCreateCommand`: container bootstrap sequence

The `postCreateCommand` runs once after the container is created. It is built as a single string of semicolon-separated steps so a failure in one step does not abort the rest.

**Step 1 — Copy host Claude config:**
```bash
cp -a /tmp/.host-claude/. ~/.claude/
rm -f ~/.claude/.credentials.json   # credentials come via CLAUDE_CODE_OAUTH_TOKEN env var
```

**Step 1b — Patch `settings.json`:**
Merges `alwaysThinkingEnabled`, `skipDangerousModePermissionPrompt`, and `effortLevel` into the copied settings. Uses `jq` to merge into the existing file or creates it from scratch.

**Step 2 — Write `~/.claude.json`:**
Marks every onboarding flag complete and trusts the container workspace path. This prevents any interactive setup dialog from blocking the agent on first launch.

**Step 3 — Copy SSH keys and gitconfig:**
```bash
cp -r /tmp/.host-ssh ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/*
cp /tmp/.host-gitconfig ~/.gitconfig
```

**Step 4 — Install Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Step 5 — Install `gh` CLI and restore auth:**
Installs `gh` via apt from the official GitHub CLI repo, then copies `~/.config/gh` from the host mount and runs `gh auth setup-git` to configure the git credential helper inside the container.

**Step 6 — Fix git worktree paths:**
The worktree's `.git` file contains an absolute host path to the bare repo. Inside the container the bare repo is mounted at `/tmp/.bare-repo`. This step rewrites the `.git` file and the corresponding `gitdir` entry in the bare repo to use the container paths:

```bash
echo 'gitdir: /tmp/.bare-repo/worktrees/<name>' > /workspaces/<name>/.git
echo '/workspaces/<name>' > /tmp/.bare-repo/worktrees/<name>/gitdir
```

This makes git operations (status, commit, push) work correctly from inside the container.

## Step 3 — Starting the container

`start_devcontainer()` runs:

```bash
devcontainer up \
  --workspace-folder <worktree_path> \
  --id-label dev-cli.session=<session_name>
```

The `--id-label` tag lets dev-cli find the container by session name as a fallback if the container ID is not in the registry (e.g. after a crash). The CLI outputs build logs on stderr and a JSON result object on stdout. The container ID is extracted from `result.containerId`.

## How the tmux session runs commands in the container

Every command that runs in a container session is prefixed with:

```bash
docker exec -it --user node <container_id> bash -lc "cd /workspaces/<name> && <command>"
```

The `-it` flags are safe here because tmux allocates a PTY for every window. The `--user node` flag must match `remoteUser` in `devcontainer.json` so that the process reads the same `~` that `postCreateCommand` wrote config files to.

`build_agent_cmd()` and `build_window_cmd()` both take an optional `container_id` argument and produce the appropriate `docker exec` prefix when it is set.

### Headless mode

In headless mode the agent is launched with `claude -p` (non-interactive `--print` mode). The initial prompt is written to `.dev-prompt` in the worktree (which is bind-mounted into the container), then read via stdin redirection:

```bash
docker exec -it --user node <cid> bash -lc \
  "cd /workspaces/<name> && claude -p --dangerously-skip-permissions < /workspaces/<name>/.dev-prompt; \
   echo ''; echo 'Agent finished. Session kept open for inspection.'; exec bash"
```

The `exec bash` at the end keeps the tmux window alive so you can inspect the state after the agent finishes.

`--dangerously-skip-permissions` is always added in headless container mode because the container itself is the sandbox — there is no risk of the agent modifying the host.

### Interactive mode

In interactive (non-headless) mode, `claude` runs normally inside the container. You interact with it by attaching to the tmux session. This mode is marked experimental because TUI rendering through `docker exec` can behave differently from a native session.

## `dev shell` in container sessions

`cmd_shell()` checks whether the session has a `container_id` in the registry. If it does, it runs:

```bash
docker exec -it --user node <cid> bash -lc "cd /workspaces/<name> && exec bash"
```

rather than attaching to the tmux shell window.

## Container cleanup

`stop_devcontainer()` runs `docker stop` followed by `docker rm` on the container. This is called by:

- `dev kill` — before removing the worktree and freeing the slot
- `dev gc` — when cleaning up sessions whose tmux session is dead

If the container ID is missing from the registry (e.g. after a partial failure), the function falls back to finding the container by its `dev-cli.session=<name>` label.

## Custom `devcontainer.json`

If the project repo already commits a `.devcontainer/devcontainer.json` or `.devcontainer.json`, dev-cli skips generation entirely and uses that file. The `postCreateCommand` from the project's config runs instead of the one dev-cli would have generated, so credentials and tool installation need to be handled by the project's own config if it overrides this.

## Project-level defaults

The project config at `~/.config/dev-cli/projects/<project>.json` can store container preferences so they apply automatically to every `dev new` for that project:

```json
{
  "use_container": true,
  "container_env": false,
  "claude_model": "claude-opus-4-5",
  "claude_effort": "high"
}
```

These are set interactively via `dev config <project>` and resolved before any flags are parsed, so per-session flags can still override them.

## Port registry fields

A container session stores these additional fields in the port registry alongside the standard slot/port entries:

| Field | Type | Description |
|---|---|---|
| `container_id` | string | Full Docker container ID |
| `use_container` | bool | True if session uses a container |
| `container_env` | bool | True if `--env` was passed |
| `headless` | bool | True if running in headless mode |
| `headless_prompt` | string | The initial prompt (if headless) |
