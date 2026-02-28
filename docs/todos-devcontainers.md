# Devcontainers — Open Items & Roadmap

Tracked issues, known gaps, and planned improvements for the devcontainer feature.

---

## Known issues

### Interactive mode is experimental

Interactive container sessions (`--container` without `--prompt`) work but TUI rendering through `docker exec` can behave differently from a native terminal. Specifically, some Claude Code UI elements may not render correctly at all terminal widths. Needs broader testing before removing the "experimental" label.

### No container rebuild path

There is currently no command to rebuild or recreate a container without killing and re-creating the entire session. If the container state gets corrupted (e.g. a failed `postCreateCommand` step), the only recovery path is `dev kill` + `dev new`.

Possible solution: add a `dev restart --rebuild <session>` flag that stops and removes the container, then re-runs `devcontainer up` against the same worktree.

### Docker image accumulation

Dev-cli does not clean up Docker images after sessions are killed. Over time, multiple versions of `mcr.microsoft.com/devcontainers/javascript-node` accumulate on disk.

Possible solution: add a `dev docker prune` command (or a `--prune-images` flag to `dev gc`) that runs `docker image prune` after garbage collection.

### `dev logs` not container-aware

`dev logs <session>` reads from the tmux pane buffer, which works for container sessions too, but does not expose Docker logs (`docker logs <cid>`). Build-time failures in `postCreateCommand` may not be visible in the tmux pane.

Possible solution: make `dev logs` check for a `container_id` and include `docker logs --tail 100 <cid>` output when present.

---

## Gaps & limitations

### Custom Dockerfile not supported

The generated `devcontainer.json` always uses a pre-built image. There is no path to use a project-specific `Dockerfile` unless the project commits its own `devcontainer.json`.

### `postCreateCommand` from a project's own `devcontainer.json` is not augmented

When a project repo ships its own `devcontainer.json`, dev-cli uses it as-is. That means the credential-forwarding and tool-installation steps from the generated config do not run. The project's config must handle Claude Code installation and credential setup itself.

Possible solution: detect the case and inject the credential-copy steps into the project's `postCreateCommand` rather than skipping them entirely.

### Codex in containers is untested at scale

`build_agent_cmd()` supports Codex inside containers, but it has received less testing than the Claude path. Edge cases around Codex authentication inside a container may exist.

### `dev send` with container sessions

`dev send <session> "<prompt>"` sends a prompt to a running agent via `tmux send-keys`. This works for container sessions because it writes to the tmux pane, but it has not been tested specifically against headless sessions (where the pane runs `claude -p`).

### Multi-agent sessions share one container

When `--agents claude,codex` is used with `--container`, both agent windows run inside the same container. This is correct (one container per worktree), but it has not been explicitly validated that both agents can run concurrently without conflict.

---

## Planned improvements

### Per-project devcontainer image override

Allow specifying a custom image in the project config:

```json
{
  "container_image": "ghcr.io/myorg/my-dev-image:latest"
}
```

This would be used by `ensure_devcontainer_json` instead of the default Node image.

### Container health check in `dev doctor`

Add a check to `dev doctor` that verifies Docker daemon health and reports how many dev-cli containers are currently running, plus total disk usage of dev-cli images.

### Smarter `secrets.env` passthrough

The `--env` flag currently passes the entire `secrets.env` as `remoteEnv`. A more targeted approach would let the project config declare exactly which keys it needs:

```json
{
  "container_secrets": ["SUPABASE_URL", "SUPABASE_ANON_KEY"]
}
```

### Session restore after host reboot

If the VPS reboots, Docker containers are gone but the port registry still holds `container_id` entries. A `dev restore` command (or logic in `dev gc`) could detect stopped containers and either clean them up or restart them.

### Web dashboard container visibility

The web dashboard shows sessions but does not expose container status (`running` / `stopped` / `not found`). Adding a container status field to the sessions page would make it easier to spot orphaned containers.
