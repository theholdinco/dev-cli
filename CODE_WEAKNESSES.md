# Code Weaknesses Analysis

An analysis of potential weaknesses, risks, and areas for improvement in the `dev-cli` codebase. This document identifies issues but does not provide fixes.

---

## 1. Security

### 1.1 Command Injection via Partial Matching

Multiple commands use `jq` with `contains()` for partial session name matching:

```bash
matches=$(jq -r "keys[] | select(contains(\"$name\"))" "$PORT_REGISTRY")
```

The `$name` variable is interpolated directly into the jq expression without sanitization. A crafted session name containing jq syntax (e.g., quotes or parentheses) could break the filter or produce unexpected matches. This pattern appears in `cmd_attach`, `cmd_kill`, `cmd_logs`, `cmd_url`, `cmd_supabase`, `cmd_diff`, `cmd_send`, `cmd_sync`, `cmd_status`, `cmd_rename`, `cmd_private`, and several others.

**Files:** `bin/dev` (lines ~1472, 1601, 1906, 1918, 1945, 2129, 2269, 2290, 2319, 2345, 2501, 2565)

### 1.2 Unquoted Variable Expansion in Shell Commands

Several places build shell commands by string concatenation with unquoted or partially-quoted variables, which could be exploited if values contain shell metacharacters:

```bash
agent_cmd="cd $worktree_path && claude${claude_flags}${prompt_arg}"
```

If `worktree_path` contains spaces or special characters, the command will break or execute unintended operations. The `create_tmux_windows` function is particularly concerning as it builds complex commands via string interpolation (line ~269):

```bash
resolved_cmd="$port_exports && cd $worktree && echo '$url_lines' && ..."
```

**Files:** `bin/dev` (lines ~1218, 269-271), `bin/dev-hub` (line ~502, 567)

### 1.3 Secrets File Sourced via String Interpolation

The secrets file is sourced by prepending it to a shell command string:

```bash
env_prefix="source $SECRETS_FILE && "
```

This string is later interpolated into tmux commands. If the secrets file path contains spaces or special characters, or if the file itself contains malicious content beyond key-value pairs, it will be executed in the agent's shell context.

**File:** `bin/dev` (lines ~1189-1191)

### 1.4 `ensure_claude_skip_prompt` Silently Modifies User Settings

The function at line 204 silently sets `skipDangerousModePermissionPrompt = true` in `~/.claude/settings.json`. This bypasses a safety confirmation dialog without user awareness, which is a security concern especially on a shared VPS.

**File:** `bin/dev` (lines 204-217)

### 1.5 Temporary Password Printed to stdout

In the `add-dev-user` script embedded in `bootstrap.sh`, the temporary password is printed to stdout (line ~559). If the bootstrap output is logged or piped, the password is exposed in plain text.

**File:** `bootstrap.sh` (line ~559)

---

## 2. Race Conditions and Concurrency

### 2.1 Port Registry Read-Then-Write Race

While writes to the port registry use `flock`, reads do not acquire the lock. This means a session could read stale data from `ports.json` while another session is in the middle of a write. For example, `find_free_slot()` reads the registry without locking:

```bash
find_free_slot() {
  for slot in $(seq 1 $MAX_SLOTS); do
    if ! jq -e "to_entries[] | select(.value.slot == $slot)" "$PORT_REGISTRY" &>/dev/null; then
```

Two simultaneous `dev new` calls could both see the same slot as free and allocate it, causing a port collision.

**File:** `bin/dev` (lines 329-337)

### 2.2 Task Registry Not Protected by File Locking

The task registry (`tasks.json`) is modified without `flock` in several places, unlike the port registry. When the task runner and a user both modify `tasks.json` concurrently, data can be lost.

**File:** `bin/dev` (line ~2548-2553, and all `cmd_task` operations)

### 2.3 `mktemp` Files Not Cleaned Up on Failure

When `jq` processing fails after `mktemp` creates a temporary file, the temp file is never cleaned up. There are no `trap` handlers to remove temp files on error. Over time this can leak files in `/tmp`.

**Files:** `bin/dev` (multiple locations using `tmp=$(mktemp)`), `install.sh` (line ~162)

---

## 3. Robustness and Error Handling

### 3.1 Silent Failures with `|| true`

Many operations suppress errors with `|| true` or redirect stderr to `/dev/null`, making failures invisible:

```bash
supabase stop 2>/dev/null || true
git worktree remove "$worktree_path" --force 2>/dev/null || { ... }
```

When Supabase or git worktree removal fails silently, orphaned resources accumulate without the user knowing.

**Files:** `bin/dev` (lines ~1726, 1736, 1745), throughout

### 3.2 `head -1` on Partial Matches Is Arbitrary

Commands like `cmd_logs`, `cmd_url`, `cmd_supabase`, etc. use `head -1` to pick the first partial match:

```bash
match=$(jq -r "keys[] | select(contains(\"$name\"))" "$PORT_REGISTRY" | head -1)
```

This silently picks one match without telling the user there were multiple. Compare with `cmd_attach` and `cmd_kill` which properly handle multiple matches with a selection prompt.

**Files:** `bin/dev` (lines ~1906, 1918, 1945, 2129, 2269, 2290, 2319, 2345, 2502, 2565)

### 3.3 `$?` Check After Command Substitution Is Unreliable

In `cmd_pr` (line ~2228):

```bash
pr_url=$(gh pr create ... 2>&1)
if [ $? -eq 0 ]; then
```

The `$?` after a command substitution can be masked by the variable assignment itself. Additionally, by capturing stderr in `$pr_url`, error messages get mixed with the URL.

**File:** `bin/dev` (lines 2222-2226)

### 3.4 No Validation of `jq` Output

The code frequently assumes `jq` will return valid output. If `ports.json` or `config.json` becomes corrupted (invalid JSON), nearly every command will fail with cryptic jq errors. There is no JSON validation on startup or before critical operations.

### 3.5 `cd` Commands Change Global State

Multiple functions use `cd` to change the working directory:

```bash
cd "$bare_dir"
cd "$worktree_path"
```

Because these run in the main shell (not subshells), a failure partway through a function leaves the working directory in an unexpected state. This can cause subsequent commands to operate in the wrong directory.

**Files:** `bin/dev` (lines ~748, 1065, 1142, 1146, 1156, 1735, 1744, 1950, 2036, 2151, 2360)

---

## 4. Code Duplication

### 4.1 Duplicated Helpers Between `bin/dev` and `bin/dev-hub`

As noted in CLAUDE.md, both files duplicate these functions:
- `get_session_field()`
- `human_readable_age()`
- `get_ip()`

Additionally, the agents-array logic (checking for `.agents` array vs `.agent` string) is duplicated in at least 4 places across both files (bin/dev lines ~467-478, bin/dev-hub lines ~267-272, 580-585). If any of these diverge, behavior will be inconsistent.

### 4.2 Repeated Port Null-Check Pattern

The pattern for checking if a port is allocated appears dozens of times:

```bash
[ "$frontend" != "null" ] && [ -n "$frontend" ]
```

This 2-part check (both "null" string and empty string) is repeated without a helper function, making it error-prone if a check is forgotten.

### 4.3 Duplicated `--agent`/`--agents` Parsing

The option parsing for `--agent`, `--agents`, `--yolo`, `--attach`, `--private`, `--prompt` is copy-pasted between `cmd_new` (line ~1000) and `cmd_pr_start` (line ~2003). Any new flag must be added to both.

### 4.4 Duplicated Agent Command Construction

The logic to build the `agent_cmd` string based on agent type appears in `cmd_new` (lines ~1216-1229), `cmd_restart` (lines ~2957-2962), and the extra-agent loop, each slightly different.

---

## 5. Scalability and Maintainability

### 5.1 Monolithic 5200+ Line Bash Script

The entire CLI is a single file (`bin/dev`) with ~5200 lines. This makes it:
- Hard to navigate and understand
- Difficult to test individual functions
- Prone to variable name collisions (all functions share global scope)
- Slow to parse on every invocation (bash must parse the entire file even for `dev help`)

### 5.2 No Automated Tests

There are no test files in the repository. The only validation mentioned is `bash -n bin/dev` (syntax check). There are no unit tests for critical functions like `slot_ports`, `find_free_slot`, `session_name`, `slugify`, or the port registry operations.

### 5.3 `cmd_kill` Recursive Calls

`cmd_kill` calls itself recursively for `--all` and `--project` modes:

```bash
cmd_kill "kill" "$s" --force
```

With 50 max slots, this creates up to 50 levels of recursion in bash, each re-parsing the arguments. A loop would be more efficient and less fragile.

**File:** `bin/dev` (lines 1566, 1591, 1623, 1674)

### 5.3 Hard-Coded Window Indices

Several places reference tmux windows by hard-coded index (e.g., `$match:2` for shell):

```bash
tmux attach-session -t "$match:2"       # cmd_shell
tmux capture-pane -t "$match:1" ...     # dev-hub get_preview
tmux switch-client -t "$name:2"         # dev-hub action_shell
```

If the configurable tmux windows feature changes the window order, these hard-coded indices will point to the wrong window.

**Files:** `bin/dev` (line 2273), `bin/dev-hub` (lines 143, 488)

---

## 6. UX Inconsistencies

### 6.1 Inconsistent Partial Match Behavior

Some commands handle multiple partial matches with a picker (`cmd_attach`, `cmd_kill`), while most just silently pick the first match (`cmd_logs`, `cmd_url`, `cmd_shell`, `cmd_diff`, `cmd_send`, `cmd_sync`, etc.). Users may get inconsistent experiences depending on which command they run.

### 6.2 `dev gc` Doesn't Clean Up Local Branches

When `dev gc` removes dead sessions, it removes worktrees and unregisters sessions, but does not delete the local git branch (unlike `cmd_kill` which does). This leaves orphaned branches in the bare repo.

**File:** `bin/dev` (lines 2653-2672)

### 6.3 `dev pr` Uses `git add -A` Without Warning

When the user selects option 1 ("Commit all changes with a message"), the code runs `git add -A` which stages everything, including potentially sensitive files like `.env.local`, secrets, or large binaries. There's no gitignore check or warning.

**File:** `bin/dev` (line 2178)

---

## 7. Bootstrap Script

### 7.1 Piped Install Scripts

The bootstrap script uses the `curl | bash` pattern for Homebrew and Tailscale:

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/.../install.sh)"
curl -fsSL https://tailscale.com/install.sh | sh
```

While common, this is a supply-chain risk: if the remote script is compromised, it runs with full user privileges.

### 7.2 Unconditional `tmux.conf` Overwrite

The bootstrap script unconditionally overwrites `~/.tmux.conf` (line ~239). If a user has customized their tmux config, all customizations are lost without backup or warning.

**File:** `bootstrap.sh` (lines 239-286)

### 7.3 No Version Pinning

Tool installations (lazygit, delta, Node.js, Codex CLI) use "latest" without pinning versions. A breaking change in any upstream tool could break the entire dev environment without any change to dev-cli itself.

**File:** `bootstrap.sh` (lines 308, 323, 156)
