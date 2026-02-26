# dev-cli: Areas of Improvement

A comprehensive audit of `bin/dev`, `bin/dev-hub`, `bootstrap.sh`, and `install.sh` covering security, functionality, code cleanliness, and UX.

---

## Security Improvements

### 1. jq Command Injection via Session Names (~20 call sites in `bin/dev`)

User-supplied session names are interpolated directly into jq filter strings throughout the codebase (e.g., `jq -r "keys[] | select(contains(\"$name\"))"` in `cmd_attach`, `cmd_kill`, `cmd_logs`, `cmd_url`, `cmd_send`, and many more). If a session name contains `"` or jq metacharacters, this breaks the expression or allows jq code injection. Since the port registry is group-writable on a shared VPS, a malicious user could craft a session entry to exploit this. The fix is to use jq's `--arg` flag (`jq -r --arg name "$name" 'keys[] | select(contains($name))'`) consistently across all call sites.

**Prompt:**
```
In bin/dev, find every instance where a bash variable is interpolated directly inside a jq filter string (e.g., jq -r "...$name..." or jq "del(.[\"$name\"])"). Replace each with jq's --arg flag for safe parameterized queries. For example, change `jq -r "keys[] | select(contains(\"$name\"))" "$PORT_REGISTRY"` to `jq -r --arg name "$name" 'keys[] | select(contains($name))' "$PORT_REGISTRY"`. Also fix `unregister_session` which uses `jq "del(.[\"$name\"])"` — change to `jq --arg name "$name" 'del(.[$name])'`. There are approximately 20 call sites to fix. Do not change any logic, only make the jq queries use --arg for variable passing.
```

---

### 2. Shell Injection via Unquoted Paths in tmux Commands (`bin/dev` and `bin/dev-hub`)

Paths like `$worktree_path` are embedded unquoted into shell command strings passed to tmux (e.g., `agent_cmd="cd $worktree_path && claude"`). If a path contains spaces or shell metacharacters, the command breaks or executes unintended code. In `bin/dev-hub`, `action_lazygit()` and `action_diff()` similarly embed `$path` unquoted into `tmux new-window` commands, where the path comes from the port registry and could contain adversarial values on a shared system.

**Prompt:**
```
In bin/dev, find all places where $worktree_path, $tmp_path, or similar path variables are embedded unquoted into shell command strings that are passed to tmux (via tmux new-session, tmux new-window, or tmux send-keys). These are in functions like create_tmux_windows, cmd_new, cmd_restart, cmd_ask, cmd_ghost, and cmd_review. Quote these paths inside the command strings, e.g., change `agent_cmd="cd $worktree_path && claude"` to `agent_cmd="cd \"$worktree_path\" && claude"`. In bin/dev-hub, do the same for action_lazygit() and action_diff() where $path is embedded unquoted in tmux new-window commands.
```

---

### 3. Prompt Injection via `--prompt` and `eval` in `cmd_ask` (`bin/dev`)

The `--prompt` flag's value is embedded into shell command strings with incomplete escaping (misses single quotes, `!`, newlines). In `cmd_ask`'s `--print` mode, `eval` is used directly with user-supplied prompt content (`eval "${env_prefix}claude --print \"\$prompt\""`), which allows arbitrary code execution via `$(cmd)` or backticks in the prompt. The `cmd_review` function also embeds `$pr_url` into command strings without any escaping, and `cmd_pr_start` passes PR titles/bodies from GitHub directly as prompts.

**Prompt:**
```
In bin/dev, fix the unsafe prompt handling in several functions:

1. In cmd_ask (around line 4534), replace the `eval "${env_prefix}claude --print \"\$prompt\""` pattern with a safe alternative: source the secrets file directly if it exists, then call `claude --print "$prompt"` without eval.

2. In cmd_new (around lines 1240-1252), replace the manual escaping of $initial_prompt (which misses single quotes, !, and newlines) with `printf -v escaped_prompt '%q' "$initial_prompt"` for proper shell escaping, or better yet, write the prompt to a temp file and pass it via stdin/file argument.

3. In cmd_review (around lines 4900-4907), quote $pr_url properly inside the command string passed to tmux.

4. In cmd_ghost and cmd_ask, apply the same fix as cmd_new for prompt escaping in the tmux command strings.
```

---

### 4. Race Condition in Slot Allocation (`bin/dev`)

`find_free_slot()` reads the registry to find a free slot, but the slot isn't actually claimed (via `register_session`) until 100+ lines later in `cmd_new`. Between these two calls, another concurrent `dev new` invocation can find the same slot available, resulting in two sessions with identical ports. On a shared VPS designed for multiple concurrent users, this will cause silent port binding failures.

**Prompt:**
```
In bin/dev, fix the race condition in slot allocation. Currently find_free_slot() finds a free slot and register_session() claims it much later. Move the slot allocation logic inside register_session() so that finding and claiming a slot happens atomically under the flock. Specifically: remove the standalone find_free_slot() call from cmd_new, and have register_session() accept a slot=-1 or slot=auto parameter that triggers it to find a free slot while holding the flock lock. Return the allocated slot so the caller can use it for subsequent operations.
```

---

### 5. Telegram Bot Token Partially Exposed in Output (`bin/dev`)

In `cmd_notify status`, the first 10 characters of the Telegram bot token are printed (`${token:0:10}...`). Bot tokens have the format `123456789:AAAA...` — 10 chars includes part of the secret hash. On a shared VPS, terminal output may be captured in logs or shared shell sessions, reducing the brute-force space for the token.

**Prompt:**
```
In bin/dev, in the cmd_notify function's status subcommand (around line 3921), change the token display from showing the first 10 characters (`${token:0:10}...`) to showing only the bot ID portion before the colon. Change to: `local bot_id="${token%%:*}"` and then display `(bot_id: ${bot_id})` instead of `(${token:0:10}...)`.
```

---

### 6. Pipe-to-Bash for Privileged Installers Without Integrity Checks (`bootstrap.sh`)

Three external scripts are downloaded and executed directly with no integrity verification: NodeSource (`curl | sudo -E bash -`), Tailscale (`curl | sh`), and Homebrew (`curl | bash`). On a VPS that will run AI agents with access to source code and secrets, a man-in-the-middle or compromised CDN achieves full root code execution. The scripts should be downloaded to temp files first, optionally verified against published checksums, then executed.

**Prompt:**
```
In bootstrap.sh, change the three pipe-to-bash install patterns to download-then-execute. For NodeSource (around line 156), Tailscale (around line 222), and Homebrew (around line 132): download each script to a temp file with curl first, then execute the temp file, then clean it up. For example, change `curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -` to: `tmp=$(mktemp); curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$tmp"; sudo -E bash "$tmp"; rm -f "$tmp"`. Add a comment noting that manual checksum verification can be added for additional security.
```

---

### 7. Port Registry Group-Writable Without Sticky Bit (`bootstrap.sh`)

`/etc/dev-cli/ports.json` is created with `g+w` permissions, meaning any member of the `devs` group can overwrite the entire registry with `echo '{}' > /etc/dev-cli/ports.json`, wiping all session metadata and causing port conflicts for every user. Adding the sticky bit on the directory would prevent users from deleting or replacing files they don't own.

**Prompt:**
```
In bootstrap.sh, where the /etc/dev-cli directory permissions are set (around line 117), add the sticky bit to prevent users from deleting or replacing files owned by other users. Change `sudo chmod g+ws /etc/dev-cli` to `sudo chmod g+ws,+t /etc/dev-cli`. Add a comment explaining that the sticky bit prevents any single user from overwriting the shared port registry.
```

---

### 8. Temporary Password Printed to Terminal in Plaintext (`bootstrap.sh`)

The `add-dev-user` function generates a temp password and prints it directly to stdout. Terminal sessions are often logged (`.bash_history`, session recording, SSH audit logs), permanently storing the cleartext credential even after the user changes it. The password should be written to a root-readable temp file instead.

**Prompt:**
```
In bootstrap.sh, in the add-dev-user heredoc (around lines 559-560), instead of printing the temporary password to stdout with echo, write it to a root-only-readable temp file. Replace the two echo lines with: create a temp file with `CRED_FILE=$(mktemp /root/new-user-creds-XXXXXX)`, `chmod 600 "$CRED_FILE"`, write the username and password to it, then print a message telling the admin to read and delete the file after securely sharing the credentials.
```

---

### 9. `cmd_update` Runs Downloaded `install.sh` Without Integrity Check (`bin/dev`)

The self-update command downloads a tarball via `gh api`, extracts it, and runs `bash "$tmp_dir/install.sh"` without verifying any checksum or signature. While the GitHub API provides some transport-level trust, a compromised API response or cached proxy could serve a malicious installer that runs with the user's full privileges.

**Prompt:**
```
In bin/dev, in cmd_update (around lines 3196-3205), add a basic integrity check after downloading and extracting the tarball. After extraction, verify that the extracted install.sh exists and is non-empty. Add a comment noting that for stronger security, a SHA256 checksum published as a GitHub release asset could be verified here. Also add a `--skip-verify` flag documentation comment for future implementation.
```

---

## Functionality Improvements

### 10. `cmd_gc` Doesn't Delete Local Git Branches (Unlike `cmd_kill`)

When `cmd_gc` cleans up dead sessions, it removes the worktree and unregisters from the registry but never deletes the local git branch. Meanwhile, `cmd_kill` properly handles branch deletion with prompts about unpushed commits. After `dev gc`, users will see confusing "branch already exists" errors when trying to create a new session on the same branch name.

**Prompt:**
```
In bin/dev, in cmd_gc (around lines 2686-2705), add branch deletion logic matching what cmd_kill does. After removing the worktree and before unregistering the session, look up the branch name from the session's registry entry, check if it has been merged or pushed (using the same logic cmd_kill uses around lines 1783-1800), and delete the local branch with `git branch -d` (or `git branch -D` for unmerged branches with a warning). Handle the case where the branch doesn't exist anymore gracefully.
```

---

### 11. `cmd_shell` Hardcodes Window Index 2 (`bin/dev`)

`cmd_shell` uses `tmux attach-session -t "$match:2"` to attach to the shell window, but the window layout is configurable via `get_tmux_windows`. If a user has a custom layout with fewer windows or a different order, this attaches to the wrong window or fails entirely. The window should be referenced by name instead of index.

**Prompt:**
```
In bin/dev, in cmd_shell (around line 2306), change `tmux attach-session -t "$match:2"` to reference the shell window by name instead of hardcoded index. Use `tmux attach-session -t "$match:shell"` to match the window named "shell" regardless of its index position. This aligns with the configurable window layout feature from get_tmux_windows.
```

---

### 12. `cmd_gc` Doesn't Handle Ghost or Ask Session Types (`bin/dev`)

`cmd_gc` assumes all sessions have a standard git worktree structure, but `ghost` sessions use `$PROJECTS_DIR/ghost` which isn't a real git repo, and `ask` sessions have a different cleanup path. `cmd_kill` correctly checks `session_type` for different cleanup logic, but `cmd_gc` does not, causing `git worktree remove` to always fail for ghost sessions and falling back to `rm -rf`.

**Prompt:**
```
In bin/dev, in cmd_gc (around lines 2686-2705), add session type checking similar to cmd_kill. Before attempting git worktree remove, read the session type from the registry with get_session_field. For "ghost" sessions, just remove the directory (no git worktree operations). For "ask" sessions, use the appropriate cleanup path. Only use `git worktree remove` for standard sessions that have a valid bare_dir.
```

---

### 13. `find_free_slot` Forks Up to 50 jq Processes (`bin/dev`)

`find_free_slot()` loops through slots 1-50 and runs a separate `jq` process for each to check if it's in use. This is unnecessarily slow and resource-intensive. A single jq call can extract all used slots, and then a bash loop can find the first gap.

**Prompt:**
```
In bin/dev, optimize find_free_slot() (around lines 358-366). Replace the loop that forks one jq process per slot with a single jq call that extracts all used slots at once. Change to: `used_slots=$(jq -r '[to_entries[].value.slot] | sort | .[]' "$PORT_REGISTRY" 2>/dev/null)`, then loop through `seq 1 $MAX_SLOTS` and use `grep -qx "$slot"` against the used_slots to find the first free one. This reduces up to 50 jq forks to exactly 1.
```

---

### 14. No File Size Check When Sending via tmux (`bin/dev`)

`cmd_send` with `--file` reads an entire file with `cat` and sends its contents via `tmux send-keys -l`, which has practical size limits (~1MB). Large or binary files will silently truncate or corrupt the agent's input. A simple size check and text validation would prevent confusing failures.

**Prompt:**
```
In bin/dev, in cmd_send (around lines 2365-2372), after reading the file contents with `prompt=$(cat "$file")`, add a size check before sending via tmux. Check that the file size is under 64KB with: `local size=$(wc -c < "$file"); [ "$size" -gt 65536 ] && die "File too large to send via tmux (max 64KB). Consider placing the file in the session's worktree instead."`. Also add a basic binary file check: `if file "$file" | grep -q 'binary'; then die "Cannot send binary file via tmux"; fi`.
```

---

### 15. `cmd_pr` Exit Code Check After if/fi Block (`bin/dev`)

In `cmd_pr`, `gh pr create` output is captured with `2>&1` into `$pr_url`, and then `$?` is checked after an `if/fi` block. This is fragile — on failure, `$pr_url` contains the error message rather than a URL, which then gets printed as a URL. The command should use `if ! pr_url=$(...)` pattern for reliable error detection.

**Prompt:**
```
In bin/dev, in cmd_pr (around lines 2255-2261), fix the fragile error checking for `gh pr create`. Replace the current pattern of capturing output with 2>&1 and checking $? afterward with: combine the draft_flag into a single call and use `if ! pr_url=$(gh pr create --title "$title" --body "" --base "$base_branch" ${draft_flag:-} 2>&1); then die "Failed to create PR: $pr_url"; fi`. This ensures the exit code is properly captured and error messages don't get printed as URLs.
```

---

### 16. Binary Downloads Hardcoded to x86_64 (`bootstrap.sh`)

The lazygit and delta binary downloads hardcode `x86_64` architecture. On ARM VPS instances (AWS Graviton, Ampere), this silently downloads the wrong binary. Additionally, if the GitHub API is rate-limited and returns empty version strings, the download URL becomes malformed and `tar` fails, aborting the entire bootstrap.

**Prompt:**
```
In bootstrap.sh, fix the lazygit download (around lines 308-311) and delta download (around lines 323-327) to detect architecture dynamically. Use `ARCH=$(dpkg --print-architecture)` and map it: amd64→x86_64, arm64→arm64. Add a check for empty version strings (GitHub API rate limit) and skip the install with a warning instead of aborting. Wrap each download in an if block that verifies the version was retrieved successfully before attempting the download.
```

---

### 17. Duplicate Aliases on Combined bootstrap.sh + install.sh Run

`bootstrap.sh` appends shell aliases to `~/.bashrc` without the `# dev-cli aliases` marker that `install.sh` checks for. When `bootstrap.sh` calls `install.sh`, the marker check passes (finds no marker), and aliases are appended a second time. Users end up with duplicate alias blocks.

**Prompt:**
```
In bootstrap.sh, remove the alias block that is appended to ~/.bashrc (around lines 393-416). The install.sh script already handles alias installation idempotently with a marker check. Since bootstrap.sh calls install.sh, the aliases will be installed once through that path. If the bootstrap aliases block includes any aliases not in install.sh, move those to install.sh's alias block instead.
```

---

### 18. `install.sh` Binary Copies Fail Cryptically If Files Missing

`install.sh` copies four binaries from `bin/` with bare `cp` commands. With `set -euo pipefail`, if any file is missing (e.g., `claude-tg-notify` not yet created), the script aborts with just a `cp: cannot stat` error and no context. Non-core binaries should be treated as optional.

**Prompt:**
```
In install.sh, replace the individual cp commands for binaries (around lines 39-47) with a loop that checks for file existence. Use a list of required binaries (dev, dev-hub) and optional binaries (claude-tg-notify, dev-task-runner). For required ones, fail with a clear error message. For optional ones, skip with a warning using the project's warn function or echo. Example: `for _bin in dev dev-hub; do [ -f "$REPO_DIR/bin/$_bin" ] || die "Required binary bin/$_bin not found"; done`.
```

---

## Code Cleanliness Improvements

### 19. Agent Command String Duplicated in 5 Functions (`bin/dev`)

The pattern for building agent command strings (`case "$primary_agent" in claude) ... ;; codex) ... ;; none) ... ;; esac`) is repeated with minor variations in `cmd_new`, `cmd_restart`, `cmd_agent add`, `cmd_ask`, and `cmd_ghost`. A bug fix or new agent type requires updating all five locations.

**Prompt:**
```
In bin/dev, extract the duplicated agent command construction into a single helper function `build_agent_cmd()` that takes agent type, worktree path, flags, and optional prompt as arguments. Replace the duplicated case statements in cmd_new (around line 1249), cmd_restart (around line 2991), cmd_agent add (around line 3551), cmd_ask (around line 4595), and cmd_ghost (around line 4732) with calls to this new function. The function should return the command string via echo or a nameref variable.
```

---

### 20. Port-Disabling Logic Duplicated (`bin/dev`)

Both `register_session` and `cmd_new` contain identical ~12-line blocks that read the project config and set `frontend`/`backend`/`supa_*` ports to `"null"` based on project flags. If the config field names ever change, both need updating.

**Prompt:**
```
In bin/dev, extract the duplicated port-nulling logic from register_session (around lines 388-398) and cmd_new (around lines 1139-1150) into a helper function called `resolve_session_ports()` that takes a project name and slot number, reads the project config, and outputs the 5 port values (frontend, backend, supa_api, supa_studio, supa_db) with appropriate nulling applied. Have both register_session and cmd_new call this function instead of duplicating the logic.
```

---

### 21. Helper Functions Out of Sync Between `bin/dev` and `bin/dev-hub`

CLAUDE.md explicitly warns to keep duplicated helpers in sync, but `get_session_field`, `get_ip`, and agent display logic have diverged between the two files. `get_ip()` in dev-hub doesn't check for tailscale existence before calling it. `get_session_field` in dev-hub suppresses errors while dev's version doesn't. The agent display logic is duplicated in dev-hub's `render()` and `action_info()` instead of being extracted into a `get_session_agents()` helper like dev has.

**Prompt:**
```
In bin/dev-hub, sync the helper functions with bin/dev:

1. Update get_ip() (around line 99) to match bin/dev's version that checks `command -v tailscale` before attempting to call it.

2. Update get_session_field() (around line 108) to use named local variables like bin/dev's version for consistency.

3. Extract the duplicated agent display logic from render() (around lines 267-271) and action_info() (around lines 580-584) into a single get_session_agents() helper function, matching the pattern used in bin/dev (around line 496). Call this helper from both render() and action_info().
```

---

### 22. Dead Code: `hub_is_compact()` Defined But Never Called (`bin/dev-hub`)

`hub_is_compact()` is defined at line 205 but never used. The `render()` function re-implements the same compact check inline. Either the function should be used or removed.

**Prompt:**
```
In bin/dev-hub, remove the unused hub_is_compact() function (around line 205), or replace the inline compact check in render() (where it does `[[ "$w" -lt 90 ]] && compact=true`) with a call to hub_is_compact(). Prefer using the function to keep the code DRY.
```

---

### 23. Recursive `cmd_kill` Uses Fragile Positional Argument Convention (`bin/dev`)

When `cmd_kill --all` processes multiple sessions, it calls itself recursively with `cmd_kill "kill" "$s" --force`, passing `"kill"` as a dummy first argument. The callee then skips index 0 to get the session name. This implicit convention is fragile and will silently break if argument parsing changes.

**Prompt:**
```
In bin/dev, refactor cmd_kill to extract the single-session kill logic into a private helper function `_kill_session()` that takes a session name and force flag. Have cmd_kill's --all path call `_kill_session "$s" true` for each session instead of recursively calling `cmd_kill "kill" "$s" --force`. This removes the fragile positional argument convention and makes the code self-documenting.
```

---

### 24. `mktemp` Files Not Cleaned Up on Failure (`bin/dev`)

Throughout `bin/dev`, `mktemp` is used to create temporary files for jq operations, but if jq fails (corrupted JSON, disk full), there's no cleanup. The temp file leaks and no error is surfaced to the user. Functions affected include `register_session`, `unregister_session`, `cmd_rename`, and `cmd_agent`.

**Prompt:**
```
In bin/dev, add error handling around mktemp/jq patterns in register_session (around line 408), unregister_session (around line 453), cmd_rename (around line 2565), and cmd_agent add/remove (around lines 3563, 3596). For each, wrap the jq command in an if block: `if ! jq ... "$PORT_REGISTRY" > "$tmp"; then rm -f "$tmp"; warn "Failed to update registry"; return 1; fi`. This ensures temp files are cleaned up on failure and the user gets feedback.
```

---

### 25. `cmd_setup` Writes JSON via Heredoc With Raw Variables (`bin/dev`)

`cmd_setup` writes project config by interpolating shell variables directly into a heredoc JSON template. If values like `$run_cmd` contain quotes, newlines, or backslashes, the resulting JSON is invalid and all subsequent reads of this config silently fail.

**Prompt:**
```
In bin/dev, in cmd_setup (around lines 984-996), replace the heredoc-based JSON writing with a jq command that properly handles escaping. Change the `cat > "$project_config" << PCONF` block to use: `jq -n --arg name "$project" --arg is_monorepo "$is_monorepo" --arg repo_url "$repo_url" --arg run_cmd "$run_cmd" '{name: $name, is_monorepo: ($is_monorepo == "true"), repo_url: $repo_url, run_cmd: $run_cmd, created: (now | strftime("%Y-%m-%dT%H:%M:%S"))}' > "$project_config"`. Adjust the field names and values to match the current heredoc exactly.
```

---

## UX Improvements

### 26. `--force` With Multiple Matches Kills All Sessions Silently (`bin/dev`)

When a user runs `dev kill feat --force` and there are 5 sessions matching "feat", all 5 are destroyed without any listing or confirmation. The `--force` flag means "skip confirmation for a single session" but silently expands to "kill every matching session." At minimum, the sessions being killed should be listed.

**Prompt:**
```
In bin/dev, in cmd_kill (around lines 1653-1659), when --force is used with multiple matches, add output listing which sessions will be killed before killing them. Before the while loop, add: `info "Killing ${match_count} sessions matching '$name':"` followed by a loop printing each match name with `echo "  - $m"`. This gives the user visibility into what --force is doing without requiring confirmation.
```

---

### 27. Attaching to a Dead Session Gives No Feedback (`bin/dev-hub`)

In the hub TUI, pressing Enter on a session with a dead tmux session (red dot) silently does nothing. The user gets no indication of why the attach failed. A brief message before the next render cycle would clarify.

**Prompt:**
```
In bin/dev-hub, in action_attach() (around lines 370-378), add an else branch when is_alive returns false. Show a brief feedback message: `else tput cup $(($(tput lines) - 2)) 0; echo -e "  ${YELLOW}Session '$name' is not running. Press 'r' to restart or 'x' to remove.${NC}"; sleep 1; fi`. This gives users actionable feedback instead of silent failure.
```

---

### 28. Input "0" in Hub's New Session Dialog Selects Last Project (`bin/dev-hub`)

In `action_new()`, entering "0" when prompted for a project number passes the `-le` check (0 is always less than list length) but then indexes `project_list[-1]`, which in bash 4+ wraps to the last element. The lower bound should be validated.

**Prompt:**
```
In bin/dev-hub, in action_new() (around line 418), add a lower bound check to the project input validation. Change `if [[ "$project_input" =~ ^[0-9]+$ ]] && [ "$project_input" -le "${#project_list[@]}" ]` to `if [[ "$project_input" =~ ^[0-9]+$ ]] && [ "$project_input" -ge 1 ] && [ "$project_input" -le "${#project_list[@]}" ]`. This prevents "0" from being accepted and silently selecting the wrong project.
```

---

### 29. `REFRESH_SECONDS` Config Value Not Validated (`bin/dev-hub`)

The hub reads `refresh_seconds` from config and uses it directly in `read -t "$REFRESH_SECONDS"`. If the config contains a non-numeric value (e.g., `"abc"` or negative), the `read` command emits an error on every 5-second refresh cycle. A simple integer validation would prevent this.

**Prompt:**
```
In bin/dev-hub, in load_config() (around lines 87-94), add validation for the REFRESH_SECONDS value. After reading the value from config, check that it's a positive integer: change the assignment to `if [ -n "$val" ] && [[ "$val" =~ ^[1-9][0-9]*$ ]]; then REFRESH_SECONDS="$val"; fi`. This silently ignores invalid config values and keeps the default.
```

---

### 30. Compact Footer Hides Working Keyboard Shortcuts (`bin/dev-hub`)

In the hub TUI, the compact footer (for terminals under 90 columns) omits `[+]` (add agent), `[r]` (refresh), and `[l]` (lazygit) shortcuts that appear in the wide footer. These keys still work — the user just doesn't know they exist. Either show abbreviated versions or add a "more keys available" hint.

**Prompt:**
```
In bin/dev-hub, in the compact footer rendering (around lines 352-355), add the missing keyboard shortcut hints. Either abbreviate them to fit (e.g., `[+]agent [r]efr [l]git`) or add a small hint line like `echo -e "  ${DIM}more: [+] [r] [l] [d] [i]${NC}"` below the compact footer so users on narrow terminals know these shortcuts exist.
```

---

### 31. Claude Code Install Failure Silently Suppressed (`bootstrap.sh`)

In the `add-dev-user` function, Claude Code installation uses `|| true` and `2>/dev/null`, which means failures are completely hidden. The script always prints "Claude Code installed" regardless of whether the install actually succeeded. Users created on a system where the install URL is down will have a broken setup with no indication.

**Prompt:**
```
In bootstrap.sh, in the add-dev-user heredoc (around line 497), remove the `|| true` and `2>/dev/null` from the Claude Code install command. Replace with a conditional: `if su - "$USERNAME" -c 'curl -fsSL https://claude.ai/install.sh | bash' 2>&1; then echo "  ✓ Claude Code installed"; else echo "  ! Claude Code installation failed — user can retry with: curl -fsSL https://claude.ai/install.sh | bash"; fi`. This gives accurate feedback about install status.
```

---

### 32. `install.sh` Creates Unexplained `~/images` Directory

`install.sh` creates `$HOME/images` with no comment or documentation explaining its purpose. This is confusing for users inspecting what the installer does. If it's used by the Telegram bot or web dashboard, it should be documented.

**Prompt:**
```
In install.sh, add a comment above the `mkdir -p "$HOME/images"` line (around line 36) explaining what this directory is used for (e.g., "# Screenshot storage for Telegram bot notifications" or whatever its actual purpose is). If this directory is no longer needed, remove the line entirely.
```

---

### 33. `bootstrap.sh` PATH Addition Only Targets `.bashrc`, Not `.zshrc`

The PATH addition for `~/.local/bin` is only written to `~/.bashrc`. If a user's shell is zsh, the PATH is never sourced. `install.sh` correctly handles both shells. The bootstrap script should match.

**Prompt:**
```
In bootstrap.sh, where ~/.local/bin is added to PATH (around lines 367-373), extend the logic to also handle ~/.zshrc, matching what install.sh does. Use a loop: `for rcfile in ~/.bashrc ~/.zshrc; do if [ -f "$rcfile" ] && ! grep -q 'local/bin' "$rcfile"; then echo -e '\n# Local binaries\nexport PATH="$HOME/.local/bin:$PATH"' >> "$rcfile"; fi; done`.
```

---

### 34. `bootstrap.sh` Calls `install.sh` via Fragile `echo N |` Pipe

`bootstrap.sh` calls `echo N | bash install.sh` to answer "no" to the bootstrap prompt. This implicit coupling means any new prompts added to `install.sh` will be silently answered with empty input. A proper `--no-bootstrap` flag would be explicit and safe.

**Prompt:**
```
In install.sh, add a --no-bootstrap flag (or check for an environment variable like SKIP_BOOTSTRAP=1) that suppresses the "Run full VPS bootstrap?" prompt at the end of the script. Then in bootstrap.sh (around line 382), change `echo N | bash install.sh` to `bash install.sh --no-bootstrap` (or `SKIP_BOOTSTRAP=1 bash install.sh`). This makes the coupling explicit and won't break if install.sh adds more prompts.
```
