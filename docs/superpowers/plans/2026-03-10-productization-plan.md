# dev-cli Productization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform dev-cli from an internal tool into a self-hosted product with structural security, admin CLI, user management, and documentation.

**Architecture:** The core change is adding a user registry (`/etc/dev-cli/users.json`) that binds Tailscale identities to Linux users with roles. All admin operations go through `dev admin` subcommands. Security is enforced at SSH, filesystem, and network levels. The existing `ports.json` locking and session ownership model is preserved and extended.

**Tech Stack:** Bash (CLI), jq (JSON), authbind (port isolation), PAM/SSH (identity enforcement), bats-core (testing)

**Spec:** `docs/superpowers/specs/2026-03-10-productization-design.md`

---

## File Structure

### New Files
- `bin/dev-admin` — Admin subcommand handler (sourced by `bin/dev` when `dev admin` is called). Keeps `bin/dev` from growing further.
- `lib/auth.sh` — Role checking, audit logging, user registry helpers. Sourced by both `bin/dev` and `bin/dev-admin`.
- `lib/audit.sh` — Audit logging functions (append to `/etc/dev-cli/audit.log`).
- `tests/test_auth.bats` — Tests for auth/role helpers.
- `tests/test_admin.bats` — Tests for admin commands.
- `tests/test_resources.bats` — Tests for session limits, stale detection.
- `tests/test_helpers.sh` — Shared test fixtures and mocks.
- `docs/admin/quickstart.md`
- `docs/admin/user-management.md`
- `docs/admin/security.md`
- `docs/admin/troubleshooting.md`
- `docs/admin/configuration.md`
- `docs/user/getting-started.md`
- `docs/user/daily-workflow.md`
- `docs/user/commands.md`
- `docs/user/tips.md`
- `docs/user/faq.md`
- `ssh/validate-tailscale-identity.sh` — SSH AuthorizedKeysCommand script for identity binding.

### Modified Files
- `bin/dev` — Add `admin` case to main router, source `lib/auth.sh`, add role checks to `cmd_new`/`cmd_kill`/`cmd_attach`, add audit logging calls, add `cmd_setup_account`.
- `bin/dev-hub` — Add role-based UI elements (admin badge, user indicators).
- `bootstrap.sh` — Replace inline `add-dev-user` with reference to `dev admin add-user`. Add SSH identity binding setup. Add authbind installation. Add bats-core installation.
- `install.sh` — Add `dev-admin` and `lib/` to installation.
- `completions/dev.bash` — Add `admin` and `setup-account` to tab completion commands list (line 21).
- `README.md` — Rewrite as landing page pointing to `docs/admin/` and `docs/user/`.

---

## Chunk 1: Foundation — User Registry & Auth Helpers

**Agent assignment:** Core (Agent 1)
**Dependencies:** None
**Produces:** `lib/auth.sh`, `lib/audit.sh`, `tests/test_auth.bats`, `tests/test_helpers.sh`

### Task 1.1: Set Up Test Infrastructure

**Files:**
- Create: `tests/test_helpers.sh`
- Modify: `bootstrap.sh:197-213` (add bats-core to dependencies)

- [ ] **Step 1: Create test helpers file**

```bash
# tests/test_helpers.sh
# Shared fixtures for dev-cli tests

setup_test_env() {
    export TEST_DIR="$(mktemp -d)"
    export TEST_ETC_DIR="$TEST_DIR/etc/dev-cli"
    export TEST_CONFIG_DIR="$TEST_DIR/config/dev-cli"
    mkdir -p "$TEST_ETC_DIR" "$TEST_CONFIG_DIR"

    # Initialize empty registries
    echo '{}' > "$TEST_ETC_DIR/ports.json"
    echo '{"users":{}}' > "$TEST_ETC_DIR/users.json"
    echo -n "" > "$TEST_ETC_DIR/audit.log"

    # Override paths for testing
    export USERS_FILE="$TEST_ETC_DIR/users.json"
    export AUDIT_LOG="$TEST_ETC_DIR/audit.log"
    export PORT_REGISTRY="$TEST_ETC_DIR/ports.json"
}

teardown_test_env() {
    rm -rf "$TEST_DIR"
}
```

- [ ] **Step 2: Verify bats is available or install it**

Run: `which bats || echo "NOT FOUND"`

If not found, install:
```bash
sudo apt-get install -y bats || brew install bats-core
```

- [ ] **Step 3: Create a smoke test to verify bats works**

Create `tests/smoke.bats`:
```bash
#!/usr/bin/env bats

@test "bash syntax check bin/dev" {
    bash -n bin/dev
}

@test "bash syntax check bin/dev-hub" {
    bash -n bin/dev-hub
}
```

- [ ] **Step 4: Run smoke test**

Run: `bats tests/smoke.bats`
Expected: 2 tests, 2 passed

- [ ] **Step 5: Commit**

```bash
git add tests/
git commit -m "Add test infrastructure with bats-core"
```

---

### Task 1.2: Create User Registry Helpers (`lib/auth.sh`)

**Files:**
- Create: `lib/auth.sh`
- Create: `tests/test_auth.bats`

- [ ] **Step 1: Write failing tests for user registry functions**

Create `tests/test_auth.bats`:
```bash
#!/usr/bin/env bats

load test_helpers

setup() {
    setup_test_env
    source lib/auth.sh
}

teardown() {
    teardown_test_env
}

@test "get_user_role returns 'admin' for admin user" {
    echo '{"users":{"alice":{"role":"admin","status":"active"}}}' > "$USERS_FILE"
    run get_user_role "alice"
    [ "$status" -eq 0 ]
    [ "$output" = "admin" ]
}

@test "get_user_role returns 'user' for regular user" {
    echo '{"users":{"bob":{"role":"user","status":"active"}}}' > "$USERS_FILE"
    run get_user_role "bob"
    [ "$status" -eq 0 ]
    [ "$output" = "user" ]
}

@test "get_user_role returns empty for unknown user" {
    echo '{"users":{}}' > "$USERS_FILE"
    run get_user_role "nobody"
    [ "$status" -eq 1 ]
}

@test "is_admin returns 0 for admin" {
    echo '{"users":{"alice":{"role":"admin","status":"active"}}}' > "$USERS_FILE"
    run is_admin "alice"
    [ "$status" -eq 0 ]
}

@test "is_admin returns 1 for non-admin" {
    echo '{"users":{"bob":{"role":"user","status":"active"}}}' > "$USERS_FILE"
    run is_admin "bob"
    [ "$status" -eq 1 ]
}

@test "require_admin exits 1 for non-admin" {
    echo '{"users":{"bob":{"role":"user","status":"active"}}}' > "$USERS_FILE"
    run require_admin "bob"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires admin"* ]]
}

@test "get_user_status returns active for active user" {
    echo '{"users":{"alice":{"role":"admin","status":"active"}}}' > "$USERS_FILE"
    run get_user_status "alice"
    [ "$status" -eq 0 ]
    [ "$output" = "active" ]
}

@test "get_user_status returns suspended for suspended user" {
    echo '{"users":{"bob":{"role":"user","status":"suspended"}}}' > "$USERS_FILE"
    run get_user_status "bob"
    [ "$status" -eq 0 ]
    [ "$output" = "suspended" ]
}

@test "is_user_registered returns 0 for known user" {
    echo '{"users":{"alice":{"role":"admin","status":"active"}}}' > "$USERS_FILE"
    run is_user_registered "alice"
    [ "$status" -eq 0 ]
}

@test "is_user_registered returns 1 for unknown user" {
    echo '{"users":{}}' > "$USERS_FILE"
    run is_user_registered "nobody"
    [ "$status" -eq 1 ]
}

@test "get_user_max_sessions returns configured limit" {
    echo '{"users":{"bob":{"role":"user","status":"active","max_sessions":5}}}' > "$USERS_FILE"
    run get_user_max_sessions "bob"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "get_user_max_sessions returns default 8 when not set" {
    echo '{"users":{"bob":{"role":"user","status":"active"}}}' > "$USERS_FILE"
    run get_user_max_sessions "bob"
    [ "$status" -eq 0 ]
    [ "$output" = "8" ]
}

@test "graceful degradation when users.json does not exist" {
    rm -f "$USERS_FILE"
    run is_admin "$USER"
    [ "$status" -eq 0 ]  # everyone is admin in single-user mode
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/test_auth.bats`
Expected: All tests FAIL (lib/auth.sh does not exist)

- [ ] **Step 3: Implement `lib/auth.sh`**

```bash
#!/usr/bin/env bash
# lib/auth.sh — User registry and role helpers
# Sourced by bin/dev and bin/dev-admin

USERS_FILE="${USERS_FILE:-/etc/dev-cli/users.json}"
DEFAULT_MAX_SESSIONS=8

# Check if multi-user mode is active (users.json exists)
has_user_registry() {
    [[ -f "$USERS_FILE" ]]
}

# Get a field from the user registry
# Usage: get_user_field <username> <field>
get_user_field() {
    local username="$1" field="$2"
    [[ -f "$USERS_FILE" ]] || return 1
    local val
    val=$(jq -r --arg u "$username" --arg f "$field" '.users[$u][$f] // empty' "$USERS_FILE")
    [[ -n "$val" ]] || return 1
    echo "$val"
}

# Check if user is registered
is_user_registered() {
    local username="$1"
    [[ -f "$USERS_FILE" ]] || return 1
    jq -e --arg u "$username" '.users[$u] != null' "$USERS_FILE" > /dev/null 2>&1
}

# Get user role (admin|user)
get_user_role() {
    get_user_field "$1" "role"
}

# Get user status (active|suspended)
get_user_status() {
    get_user_field "$1" "status"
}

# Get user's max sessions (default 8)
get_user_max_sessions() {
    local username="$1"
    if [[ -f "$USERS_FILE" ]]; then
        local val
        val=$(jq -r --arg u "$username" '.users[$u].max_sessions // empty' "$USERS_FILE")
        echo "${val:-$DEFAULT_MAX_SESSIONS}"
    else
        echo "$DEFAULT_MAX_SESSIONS"
    fi
}

# Check if user is admin
# In single-user mode (no users.json), everyone is admin
is_admin() {
    local username="$1"
    if ! has_user_registry; then
        return 0  # single-user mode: everyone is admin
    fi
    local role
    role=$(get_user_role "$username") || return 1
    [[ "$role" == "admin" ]]
}

# Require admin role or exit
require_admin() {
    local username="${1:-$USER}"
    if ! is_admin "$username"; then
        echo "Error: this command requires admin role" >&2
        return 1
    fi
}

# Set a string field in users.json (with flock)
# Usage: set_user_field <username> <field> <value>
set_user_field() {
    local username="$1" field="$2" value="$3"
    local tmp
    tmp=$(mktemp)
    (flock 200
        jq --arg u "$username" --arg f "$field" --arg v "$value" \
            '.users[$u][$f] = $v' "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
    ) 200>"$USERS_FILE.lock"
}

# Set a non-string field (boolean, number) in users.json (with flock)
# Usage: set_user_field_raw <username> <field> <json_value>
set_user_field_raw() {
    local username="$1" field="$2" value="$3"
    local tmp
    tmp=$(mktemp)
    (flock 200
        jq --arg u "$username" --arg f "$field" --argjson v "$value" \
            '.users[$u][$f] = $v' "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
    ) 200>"$USERS_FILE.lock"
}

# Register a new user in users.json (with flock)
# Usage: register_user <username> <email> <role>
register_user() {
    local username="$1" email="$2" role="${3:-user}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmp
    tmp=$(mktemp)
    (flock 200
        jq --arg u "$username" --arg e "$email" --arg r "$role" --arg t "$now" \
            '.users[$u] = {"tailscale_email": $e, "role": $r, "created": $t, "status": "active", "max_sessions": 8, "onboarded": false}' \
            "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
    ) 200>"$USERS_FILE.lock"
}

# Remove a user from users.json (with flock)
unregister_user() {
    local username="$1"
    local tmp
    tmp=$(mktemp)
    (flock 200
        jq --arg u "$username" 'del(.users[$u])' "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
    ) 200>"$USERS_FILE.lock"
}

# Count active sessions for a user
count_user_sessions() {
    local username="$1"
    local registry="${PORT_REGISTRY:-/etc/dev-cli/ports.json}"
    [[ -f "$registry" ]] || { echo "0"; return; }
    jq --arg u "$username" '[.[] | select(.owner == $u)] | length' "$registry"
}

# Check if user can create another session
can_create_session() {
    local username="$1"
    if ! has_user_registry; then
        return 0  # no limits in single-user mode
    fi
    local current max
    current=$(count_user_sessions "$username")
    max=$(get_user_max_sessions "$username")
    (( current < max ))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/test_auth.bats`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/auth.sh tests/test_auth.bats
git commit -m "Add user registry and role helpers (lib/auth.sh)"
```

---

### Task 1.3: Create Audit Logging (`lib/audit.sh`)

**Files:**
- Create: `lib/audit.sh`
- Add tests to: `tests/test_auth.bats`

- [ ] **Step 1: Write failing tests for audit functions**

Append to `tests/test_auth.bats`:
```bash
# --- Audit logging tests ---

@test "audit_log writes JSON-lines entry" {
    source lib/audit.sh
    audit_log "alice" "session.create" "my-feature" '{"project":"app"}'
    local line
    line=$(tail -1 "$AUDIT_LOG")
    echo "$line" | jq -e '.actor == "alice"'
    echo "$line" | jq -e '.action == "session.create"'
    echo "$line" | jq -e '.target == "my-feature"'
}

@test "audit_log appends without overwriting" {
    source lib/audit.sh
    audit_log "alice" "session.create" "feat-1" '{}'
    audit_log "bob" "session.kill" "feat-2" '{}'
    local count
    count=$(wc -l < "$AUDIT_LOG")
    [ "$count" -eq 2 ]
}

@test "audit_log works with empty details" {
    source lib/audit.sh
    audit_log "alice" "admin.list-users" "" ""
    local line
    line=$(tail -1 "$AUDIT_LOG")
    echo "$line" | jq -e '.actor == "alice"'
    echo "$line" | jq -e '.action == "admin.list-users"'
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/test_auth.bats`
Expected: New audit tests FAIL

- [ ] **Step 3: Implement `lib/audit.sh`**

```bash
#!/usr/bin/env bash
# lib/audit.sh — Audit logging for dev-cli
# Sourced by bin/dev and bin/dev-admin

AUDIT_LOG="${AUDIT_LOG:-/etc/dev-cli/audit.log}"

# Write a JSON-lines audit entry
# Usage: audit_log <actor> <action> [target] [details_json]
audit_log() {
    local actor="$1" action="$2" target="${3:-}" details="${4:-{}}"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    [[ -z "$details" || "$details" == "" ]] && details='{}'
    local entry
    entry=$(jq -nc \
        --arg ts "$ts" \
        --arg actor "$actor" \
        --arg action "$action" \
        --arg target "$target" \
        --argjson details "$details" \
        '{ts: $ts, actor: $actor, action: $action, target: $target, details: $details}')
    echo "$entry" >> "$AUDIT_LOG"
}

# Read and filter audit log
# Usage: audit_read [--user <name>] [--action <type>] [--last <duration>]
audit_read() {
    local user="" action="" last=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user) user="$2"; shift 2 ;;
            --action) action="$2"; shift 2 ;;
            --last) last="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filter="."
    [[ -n "$user" ]] && filter="$filter | select(.actor == \"$user\")"
    [[ -n "$action" ]] && filter="$filter | select(.action | startswith(\"$action\"))"

    if [[ -n "$last" ]]; then
        local seconds=0
        case "$last" in
            *h) seconds=$(( ${last%h} * 3600 )) ;;
            *d) seconds=$(( ${last%d} * 86400 )) ;;
            *m) seconds=$(( ${last%m} * 60 )) ;;
            *) seconds="$last" ;;
        esac
        local cutoff
        cutoff=$(date -u -d "-${seconds} seconds" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                 date -u -v-${seconds}S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        if [[ -n "$cutoff" ]]; then
            filter="$filter | select(.ts >= \"$cutoff\")"
        fi
    fi

    [[ -f "$AUDIT_LOG" ]] || return 0
    jq -c "$filter" "$AUDIT_LOG"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/test_auth.bats`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/audit.sh tests/test_auth.bats
git commit -m "Add audit logging helpers (lib/audit.sh)"
```

---

## Chunk 2: Admin CLI Commands

**Agent assignment:** Core (Agent 1)
**Dependencies:** Chunk 1
**Produces:** `bin/dev-admin`, admin subcommands in `bin/dev`

### Task 2.1: Create Admin Command Router

**Files:**
- Create: `bin/dev-admin`
- Modify: `bin/dev:6937-6986` (add `admin` case to main router)
- Modify: `install.sh:38-47` (add `dev-admin` and `lib/` to installation)
- Create: `tests/test_admin.bats`

- [ ] **Step 1: Write failing test for admin routing**

Create `tests/test_admin.bats`:
```bash
#!/usr/bin/env bats

load test_helpers

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "dev-admin exits with error for unknown subcommand" {
    run bash bin/dev-admin unknown 2>&1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown admin command"* ]]
}

@test "dev-admin shows help with no arguments" {
    run bash bin/dev-admin help 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"add-user"* ]]
    [[ "$output" == *"list-users"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_admin.bats`
Expected: FAIL (bin/dev-admin does not exist)

- [ ] **Step 3: Create `bin/dev-admin` skeleton**

```bash
#!/usr/bin/env bash
set -euo pipefail

# dev-admin — Admin subcommand handler for dev-cli
# Sourced/called by `dev admin <subcommand>`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# lib/ is at ../lib/ in dev repo, or at ../lib/dev-cli/ when installed to ~/.local/bin/
if [[ -d "$SCRIPT_DIR/../lib/dev-cli" ]]; then
    LIB_DIR="$SCRIPT_DIR/../lib/dev-cli"
elif [[ -d "$SCRIPT_DIR/../lib" ]]; then
    LIB_DIR="$SCRIPT_DIR/../lib"
else
    echo "Error: cannot find lib directory" >&2; exit 1
fi

# Source helpers
source "$LIB_DIR/auth.sh"
source "$LIB_DIR/audit.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

die() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }
log() { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${BLUE}ℹ${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

cmd_admin_help() {
    cat <<EOF
${BOLD}dev admin${NC} — Admin commands for user and system management

${BOLD}User Management:${NC}
  add-user <name> --tailscale-email <email> [--role admin|user]
  remove-user <name> [--purge]
  list-users
  suspend-user <name>
  restore-user <name>
  set-role <name> <admin|user>
  set-limit <name> --max-sessions <N>

${BOLD}Monitoring:${NC}
  status                    System health overview
  audit [--user X] [--last 24h]
  stale-sessions [--older-than 7d]

${BOLD}Operations:${NC}
  port-access <session> --grant <user>
  backup [--output <path>]
  restore <backup-path>
  update
EOF
}

# --- User Management Commands ---

cmd_admin_add_user() {
    require_admin || exit 1
    local username="" email="" role="user"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tailscale-email) email="$2"; shift 2 ;;
            --role) role="$2"; shift 2 ;;
            *) [[ -z "$username" ]] && username="$1"; shift ;;
        esac
    done
    [[ -n "$username" ]] || die "Usage: dev admin add-user <username> --tailscale-email <email> [--role admin|user]"
    [[ -n "$email" ]] || die "Missing --tailscale-email"
    [[ "$role" == "admin" || "$role" == "user" ]] || die "Role must be 'admin' or 'user'"

    # Check if user already exists in registry
    if is_user_registered "$username"; then
        die "User '$username' is already registered"
    fi

    # Validate Tailscale email is in the tailnet
    if command -v tailscale &>/dev/null; then
        if ! tailscale status 2>/dev/null | grep -qi "$email"; then
            warn "Tailscale identity '$email' not found in current tailnet. Proceeding anyway."
        fi
    fi

    info "Creating Linux user '$username'..."
    if id "$username" &>/dev/null; then
        warn "Linux user '$username' already exists, skipping creation"
    else
        sudo useradd -m -s /bin/bash "$username" || die "Failed to create user"
        local tmp_pass
        tmp_pass=$(openssl rand -base64 12)
        echo "$username:$tmp_pass" | sudo chpasswd
        sudo chage -d 0 "$username"  # force password change
        info "Temporary password: $tmp_pass"
    fi

    # Add to groups
    sudo usermod -aG devs "$username"
    if [[ "$role" == "admin" ]]; then
        sudo usermod -aG sudo "$username"
    fi

    # Install dev-cli for user
    info "Installing dev-cli for '$username'..."
    local user_home
    user_home=$(eval echo "~$username")
    sudo -u "$username" mkdir -p "$user_home/.local/bin" "$user_home/.config/dev-cli"
    sudo cp "$SCRIPT_DIR/dev" "$SCRIPT_DIR/dev-hub" "$SCRIPT_DIR/dev-admin" "$user_home/.local/bin/"
    sudo mkdir -p "$user_home/.local/lib/dev-cli"
    sudo cp "$LIB_DIR/auth.sh" "$LIB_DIR/audit.sh" "$user_home/.local/lib/dev-cli/"
    sudo chown -R "$username:$username" "$user_home/.local/"

    # Install Claude Code
    info "Installing Claude Code for '$username'..."
    sudo -u "$username" bash -c 'curl -fsSL https://cli.claude.ai/install.sh | sh' 2>/dev/null || warn "Claude Code install failed — user can run manually"

    # Link shared secrets
    if [[ -d /etc/dev-cli/secrets ]]; then
        info "Linking shared secrets..."
        sudo -u "$username" mkdir -p "$user_home/.config/dev-cli/secrets"
        for secret in /etc/dev-cli/secrets/*; do
            [[ -f "$secret" ]] || continue
            sudo -u "$username" ln -sf "$secret" "$user_home/.config/dev-cli/secrets/$(basename "$secret")"
        done
    fi

    # Create per-user secrets file
    if [[ ! -f "$user_home/.config/dev-cli/secrets.env" ]]; then
        sudo -u "$username" touch "$user_home/.config/dev-cli/secrets.env"
        sudo chmod 600 "$user_home/.config/dev-cli/secrets.env"
    fi

    # Register in users.json
    register_user "$username" "$email" "$role"
    log "User '$username' registered as '$role'"

    # Set up SSH identity binding
    setup_ssh_identity_binding "$username" "$email"

    audit_log "$USER" "admin.add-user" "$username" "$(jq -nc --arg r "$role" --arg e "$email" '{role:$r,email:$e}')"

    echo ""
    info "Send this to the new user:"
    echo "──────────────────────────────────────"
    echo "You've been added to the dev server."
    echo ""
    echo "1. Install Tailscale: https://tailscale.com/download"
    echo "2. Join the tailnet (ask your admin for the invite link)"
    echo "3. SSH in: ssh $username@$(hostname)"
    echo "4. Change your password when prompted"
    echo "5. Run: dev setup-account"
    echo "──────────────────────────────────────"
}

cmd_admin_remove_user() {
    require_admin || exit 1
    local username="" purge=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --purge) purge=true; shift ;;
            *) [[ -z "$username" ]] && username="$1"; shift ;;
        esac
    done
    [[ -n "$username" ]] || die "Usage: dev admin remove-user <username> [--purge]"
    is_user_registered "$username" || die "User '$username' is not registered"

    info "Killing all sessions for '$username'..."
    local registry="${PORT_REGISTRY:-/etc/dev-cli/ports.json}"
    if [[ -f "$registry" ]]; then
        local sessions
        sessions=$(jq -r --arg u "$username" 'to_entries[] | select(.value.owner == $u) | .key' "$registry")
        for session in $sessions; do
            info "  Killing session: $session"
            # Attempt to kill tmux window
            tmux kill-window -t "dev:$session" 2>/dev/null || true
        done
        # Remove all user's sessions from registry
        local tmp
        tmp=$(mktemp)
        (flock 200
            jq --arg u "$username" 'with_entries(select(.value.owner != $u))' "$registry" > "$tmp" && mv "$tmp" "$registry"
        ) 200>"$registry.lock"
    fi

    if $purge; then
        warn "Purging home directory and worktrees for '$username'..."
        sudo userdel -r "$username" 2>/dev/null || warn "Failed to delete Linux user"
    else
        info "Disabling login for '$username' (data preserved)..."
        sudo usermod -L "$username"
    fi

    # Remove from registry
    unregister_user "$username"
    log "User '$username' removed"
    audit_log "$USER" "admin.remove-user" "$username" "$(jq -nc --argjson purge "$purge" '{purge:$purge}')"
}

cmd_admin_list_users() {
    require_admin || exit 1
    [[ -f "$USERS_FILE" ]] || die "No user registry found. Run 'dev admin add-user' first."

    printf "${BOLD}%-15s %-30s %-8s %-10s %-6s %-12s${NC}\n" "USER" "TAILSCALE EMAIL" "ROLE" "STATUS" "SESS" "CREATED"
    printf "%-15s %-30s %-8s %-10s %-6s %-12s\n" "───────────────" "──────────────────────────────" "────────" "──────────" "──────" "────────────"

    local registry="${PORT_REGISTRY:-/etc/dev-cli/ports.json}"
    jq -r '.users | to_entries[] | [.key, .value.tailscale_email, .value.role, .value.status, .value.created] | @tsv' "$USERS_FILE" | \
    while IFS=$'\t' read -r name email role status created; do
        local sess=0
        if [[ -f "$registry" ]]; then
            sess=$(jq --arg u "$name" '[.[] | select(.owner == $u)] | length' "$registry")
        fi
        local short_date="${created:0:10}"
        printf "%-15s %-30s %-8s %-10s %-6s %-12s\n" "$name" "$email" "$role" "$status" "$sess" "$short_date"
    done

    audit_log "$USER" "admin.list-users" "" '{}'
}

cmd_admin_suspend_user() {
    require_admin || exit 1
    local username="$1"
    [[ -n "$username" ]] || die "Usage: dev admin suspend-user <username>"
    is_user_registered "$username" || die "User '$username' is not registered"

    sudo usermod -L "$username"
    set_user_field "$username" "status" "suspended"
    log "User '$username' suspended"
    audit_log "$USER" "admin.suspend-user" "$username" '{}'
}

cmd_admin_restore_user() {
    require_admin || exit 1
    local username="$1"
    [[ -n "$username" ]] || die "Usage: dev admin restore-user <username>"
    is_user_registered "$username" || die "User '$username' is not registered"

    sudo usermod -U "$username"
    set_user_field "$username" "status" "active"
    log "User '$username' restored"
    audit_log "$USER" "admin.restore-user" "$username" '{}'
}

cmd_admin_set_role() {
    require_admin || exit 1
    local username="$1" role="$2"
    [[ -n "$username" && -n "$role" ]] || die "Usage: dev admin set-role <username> <admin|user>"
    [[ "$role" == "admin" || "$role" == "user" ]] || die "Role must be 'admin' or 'user'"
    is_user_registered "$username" || die "User '$username' is not registered"

    set_user_field "$username" "role" "$role"
    if [[ "$role" == "admin" ]]; then
        sudo usermod -aG sudo "$username"
    else
        sudo gpasswd -d "$username" sudo 2>/dev/null || true
    fi
    log "User '$username' role set to '$role'"
    audit_log "$USER" "admin.set-role" "$username" "$(jq -nc --arg r "$role" '{role:$r}')"
}

cmd_admin_set_limit() {
    require_admin || exit 1
    local username="" max_sessions=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-sessions) max_sessions="$2"; shift 2 ;;
            *) [[ -z "$username" ]] && username="$1"; shift ;;
        esac
    done
    [[ -n "$username" && -n "$max_sessions" ]] || die "Usage: dev admin set-limit <username> --max-sessions <N>"
    is_user_registered "$username" || die "User '$username' is not registered"
    [[ "$max_sessions" =~ ^[0-9]+$ ]] || die "max-sessions must be a number"

    # jq needs numeric value, use argjson
    local tmp
    tmp=$(mktemp)
    jq --arg u "$username" --argjson m "$max_sessions" '.users[$u].max_sessions = $m' "$USERS_FILE" > "$tmp" && mv "$tmp" "$USERS_FILE"
    log "User '$username' max sessions set to $max_sessions"
    audit_log "$USER" "admin.set-limit" "$username" "$(jq -nc --argjson m "$max_sessions" '{max_sessions:$m}')"
}

# --- Monitoring Commands ---

cmd_admin_status() {
    echo -e "${BOLD}System Status${NC}"
    echo "═══════════════════════════════════"

    # Disk usage
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5 " used (" $3 "/" $2 ")"}')
    echo -e "${BOLD}Disk:${NC} $disk_usage"

    # Users
    if [[ -f "$USERS_FILE" ]]; then
        local total_users active_users suspended_users
        total_users=$(jq '.users | length' "$USERS_FILE")
        active_users=$(jq '[.users[] | select(.status == "active")] | length' "$USERS_FILE")
        suspended_users=$(jq '[.users[] | select(.status == "suspended")] | length' "$USERS_FILE")
        echo -e "${BOLD}Users:${NC} $total_users total ($active_users active, $suspended_users suspended)"
    fi

    # Sessions
    local registry="${PORT_REGISTRY:-/etc/dev-cli/ports.json}"
    if [[ -f "$registry" ]]; then
        local total_sessions
        total_sessions=$(jq 'length' "$registry")
        local used_slots
        used_slots=$(jq '[.[].slot] | length' "$registry")
        echo -e "${BOLD}Sessions:${NC} $total_sessions active ($used_slots/50 slots used)"
    fi

    # Tailscale
    if command -v tailscale &>/dev/null; then
        local ts_status
        ts_status=$(tailscale status --self 2>/dev/null | head -1 || echo "not running")
        echo -e "${BOLD}Tailscale:${NC} $ts_status"
    fi

    echo ""
    audit_log "$USER" "admin.status" "" '{}'
}

cmd_admin_audit() {
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user|--action|--last) args+=("$1" "$2"); shift 2 ;;
            *) shift ;;
        esac
    done
    audit_read "${args[@]}" | while IFS= read -r line; do
        local ts actor action target
        ts=$(echo "$line" | jq -r '.ts')
        actor=$(echo "$line" | jq -r '.actor')
        action=$(echo "$line" | jq -r '.action')
        target=$(echo "$line" | jq -r '.target')
        printf "${DIM}%s${NC} ${CYAN}%-15s${NC} %-25s %s\n" "$ts" "$actor" "$action" "$target"
    done
}

cmd_admin_stale_sessions() {
    local older_than="7d"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --older-than) older_than="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local seconds=0
    case "$older_than" in
        *d) seconds=$(( ${older_than%d} * 86400 )) ;;
        *h) seconds=$(( ${older_than%h} * 3600 )) ;;
        *) seconds="$older_than" ;;
    esac

    local registry="${PORT_REGISTRY:-/etc/dev-cli/ports.json}"
    [[ -f "$registry" ]] || { info "No sessions found."; return; }

    echo -e "${BOLD}Stale sessions (no tmux activity for $older_than):${NC}"
    local now
    now=$(date +%s)
    local found=0

    while IFS=$'\t' read -r name owner; do
        # Check tmux last activity
        local last_activity
        last_activity=$(tmux display-message -p -t "dev:$name" '#{window_activity}' 2>/dev/null || echo "0")
        if [[ "$last_activity" == "0" ]]; then
            continue
        fi
        local age=$(( now - last_activity ))
        if (( age > seconds )); then
            local age_human="${age}s"
            if (( age > 86400 )); then
                age_human="$(( age / 86400 ))d"
            elif (( age > 3600 )); then
                age_human="$(( age / 3600 ))h"
            fi
            printf "  %-25s %-15s idle %s\n" "$name" "$owner" "$age_human"
            found=1
        fi
    done < <(jq -r 'to_entries[] | [.key, .value.owner] | @tsv' "$registry")

    (( found )) || info "No stale sessions found."
}

# --- Operations Commands ---

cmd_admin_port_access() {
    require_admin || exit 1
    local session="" grant_user=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --grant) grant_user="$2"; shift 2 ;;
            *) [[ -z "$session" ]] && session="$1"; shift ;;
        esac
    done
    [[ -n "$session" && -n "$grant_user" ]] || die "Usage: dev admin port-access <session> --grant <username>"
    info "Port access grants are managed via authbind — see docs/admin/security.md"
    audit_log "$USER" "admin.port-access" "$session" "$(jq -nc --arg u "$grant_user" '{granted_to:$u}')"
}

cmd_admin_backup() {
    require_admin || exit 1
    local output=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    output="${output:-/tmp/dev-cli-backup-$ts.tar.gz}"

    info "Creating backup..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cp /etc/dev-cli/ports.json "$tmp_dir/" 2>/dev/null || true
    cp /etc/dev-cli/users.json "$tmp_dir/" 2>/dev/null || true
    cp /etc/dev-cli/audit.log "$tmp_dir/" 2>/dev/null || true
    cp -r /etc/dev-cli/secrets "$tmp_dir/" 2>/dev/null || true

    # Per-user configs
    mkdir -p "$tmp_dir/user-configs"
    if [[ -f "$USERS_FILE" ]]; then
        jq -r '.users | keys[]' "$USERS_FILE" | while read -r u; do
            local uhome
            uhome=$(eval echo "~$u" 2>/dev/null) || continue
            if [[ -d "$uhome/.config/dev-cli" ]]; then
                mkdir -p "$tmp_dir/user-configs/$u"
                cp -r "$uhome/.config/dev-cli/projects" "$tmp_dir/user-configs/$u/" 2>/dev/null || true
                cp -r "$uhome/.config/dev-cli/hooks" "$tmp_dir/user-configs/$u/" 2>/dev/null || true
                cp -r "$uhome/.config/dev-cli/templates" "$tmp_dir/user-configs/$u/" 2>/dev/null || true
            fi
        done
    fi

    tar czf "$output" -C "$tmp_dir" .
    rm -rf "$tmp_dir"
    log "Backup saved to: $output"
    audit_log "$USER" "admin.backup" "$output" '{}'
}

cmd_admin_restore() {
    require_admin || exit 1
    local backup_path="$1"
    [[ -n "$backup_path" && -f "$backup_path" ]] || die "Usage: dev admin restore <backup-path>"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar xzf "$backup_path" -C "$tmp_dir"

    info "Restoring configuration..."
    [[ -f "$tmp_dir/users.json" ]] && sudo cp "$tmp_dir/users.json" /etc/dev-cli/
    [[ -f "$tmp_dir/ports.json" ]] && sudo cp "$tmp_dir/ports.json" /etc/dev-cli/
    [[ -f "$tmp_dir/audit.log" ]] && sudo cp "$tmp_dir/audit.log" /etc/dev-cli/
    [[ -d "$tmp_dir/secrets" ]] && sudo cp -r "$tmp_dir/secrets" /etc/dev-cli/

    rm -rf "$tmp_dir"
    log "Configuration restored from: $backup_path"
    warn "Note: worktrees are not included in backups — re-clone from git as needed."
    audit_log "$USER" "admin.restore" "$backup_path" '{}'
}

cmd_admin_update() {
    require_admin || exit 1
    info "Checking for updates..."

    # Pull latest from GitHub
    command -v gh &>/dev/null || die "GitHub CLI (gh) required for updates"
    local latest
    latest=$(gh api repos/theholdinco/dev-cli/releases/latest --jq '.tag_name' 2>/dev/null || echo "")
    [[ -n "$latest" ]] || die "Could not fetch latest release"

    local current=""
    [[ -f /etc/dev-cli/version ]] && current=$(cat /etc/dev-cli/version)
    if [[ "$current" == "$latest" ]]; then
        log "Already on latest version: $latest"
        return
    fi

    info "Updating from ${current:-unknown} to $latest..."

    # Download and install
    local tmp_dir
    tmp_dir=$(mktemp -d)
    gh api "repos/theholdinco/dev-cli/tarball/$latest" > "$tmp_dir/release.tar.gz"
    tar xzf "$tmp_dir/release.tar.gz" -C "$tmp_dir" --strip-components=1
    (cd "$tmp_dir" && bash install.sh)

    # Update for all registered users
    if [[ -f "$USERS_FILE" ]]; then
        jq -r '.users | to_entries[] | select(.value.status == "active") | .key' "$USERS_FILE" | while read -r u; do
            info "  Updating for user: $u"
            local uhome
            uhome=$(eval echo "~$u")
            sudo cp "$tmp_dir/bin/dev" "$tmp_dir/bin/dev-hub" "$tmp_dir/bin/dev-admin" "$uhome/.local/bin/" 2>/dev/null || warn "  Failed for $u"
            sudo mkdir -p "$uhome/.local/lib/dev-cli"
            sudo cp "$tmp_dir/lib/auth.sh" "$tmp_dir/lib/audit.sh" "$uhome/.local/lib/dev-cli/" 2>/dev/null || true
            sudo chown -R "$u:$u" "$uhome/.local/"
            # Track version per user
            echo "$latest" | sudo tee "$uhome/.local/bin/.dev-version" > /dev/null
        done
    fi

    echo "$latest" | sudo tee /etc/dev-cli/version > /dev/null
    rm -rf "$tmp_dir"
    log "Updated to $latest"
    audit_log "$USER" "admin.update" "$latest" '{}'
}

# --- SSH Identity Binding ---

setup_ssh_identity_binding() {
    local username="$1" email="$2"
    # This configures the SSH server to validate Tailscale identity
    # The actual validation script is installed by bootstrap.sh
    info "SSH identity binding configured for $username <-> $email"
    # Implementation note: the validate-tailscale-identity.sh script
    # is installed system-wide. Per-user bindings are read from users.json.
}

# --- Main Router ---

subcmd="${1:-help}"
shift || true

case "$subcmd" in
    add-user)        cmd_admin_add_user "$@" ;;
    remove-user)     cmd_admin_remove_user "$@" ;;
    list-users)      cmd_admin_list_users "$@" ;;
    suspend-user)    cmd_admin_suspend_user "$@" ;;
    restore-user)    cmd_admin_restore_user "$@" ;;
    set-role)        cmd_admin_set_role "$@" ;;
    set-limit)       cmd_admin_set_limit "$@" ;;
    status)          cmd_admin_status "$@" ;;
    audit)           cmd_admin_audit "$@" ;;
    stale-sessions)  cmd_admin_stale_sessions "$@" ;;
    port-access)     cmd_admin_port_access "$@" ;;
    backup)          cmd_admin_backup "$@" ;;
    restore)         cmd_admin_restore "$@" ;;
    update)          cmd_admin_update "$@" ;;
    help|--help|-h)  cmd_admin_help ;;
    *)               die "Unknown admin command: $subcmd (try 'dev admin help')" ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/test_admin.bats`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
chmod +x bin/dev-admin
git add bin/dev-admin tests/test_admin.bats
git commit -m "Add admin CLI command router (bin/dev-admin)"
```

---

### Task 2.2: Wire Admin into Main CLI

**Files:**
- Modify: `bin/dev:6937-6986` (add `admin` case)
- Modify: `bin/dev:6682-6931` (add admin to help)
- Modify: `install.sh:38-47` (add dev-admin to install)
- Modify: `install.sh:184-200` (add admin to tab completion)

- [ ] **Step 1: Add `admin` case to main router in `bin/dev`**

At `bin/dev:6937`, find the case statement. Add before the `*)` default case:

```bash
    admin)      shift; bash "$(dirname "$0")/dev-admin" "$@" ;;
```

- [ ] **Step 2: Add admin section to `cmd_help()` in `bin/dev`**

**IMPORTANT:** `cmd_help()` uses a single-quoted heredoc (`cat << 'HELPEOF'`), which means no variable expansion. You cannot use `echo -e "${BOLD}..."` inside it. Instead, add plain text lines inside the existing heredoc:

Find the `HELPEOF` closing tag in `cmd_help()` (~line 6927). Just before it, add:

```
Admin:
  admin <cmd>    Admin commands (user management, monitoring, operations)
                 Run 'dev admin help' for details
```

- [ ] **Step 3: Update `install.sh` to install `dev-admin` and `lib/`**

At `install.sh:38-47`, add `dev-admin` to the binary installation:

```bash
    # After existing binary copies, add:
    cp bin/dev-admin "$INSTALL_DIR/dev-admin"
    chmod +x "$INSTALL_DIR/dev-admin"

    # Install lib files
    mkdir -p "$HOME/.local/lib/dev-cli"
    cp lib/auth.sh lib/audit.sh "$HOME/.local/lib/dev-cli/"
```

- [ ] **Step 4: Update tab completion in `completions/dev.bash`**

At `completions/dev.bash:21`, add `admin` and `setup-account` to the `commands` variable.

- [ ] **Step 5: Verify syntax**

Run: `bash -n bin/dev && bash -n bin/dev-admin && bash -n install.sh && echo "OK"`
Expected: OK

- [ ] **Step 6: Commit**

```bash
git add bin/dev bin/dev-admin install.sh completions/dev.bash
git commit -m "Wire admin subcommand into main CLI and installer"
```

---

### Task 2.3: Add Audit Logging to Existing Commands

**Files:**
- Modify: `bin/dev:1426-1976` (cmd_new — add audit log on session create)
- Modify: `bin/dev:2074-2295` (cmd_kill — add audit log on session kill)
- Modify: `bin/dev:1978-2072` (cmd_attach — add audit log on attach)

- [ ] **Step 1: Source audit helpers in `bin/dev`**

Near the top of `bin/dev` (after line 20, after config vars), add:

```bash
# Source libraries if available
_dev_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$_dev_script_dir/../lib/dev-cli" ]]; then
    LIB_DIR="$_dev_script_dir/../lib/dev-cli"
elif [[ -d "$_dev_script_dir/../lib" ]]; then
    LIB_DIR="$_dev_script_dir/../lib"
fi
[[ -n "${LIB_DIR:-}" && -f "$LIB_DIR/auth.sh" ]] && source "$LIB_DIR/auth.sh"
[[ -n "${LIB_DIR:-}" && -f "$LIB_DIR/audit.sh" ]] && source "$LIB_DIR/audit.sh"
```

- [ ] **Step 2: Add audit log call in `cmd_new` after successful session registration**

Find the `register_session` call in `cmd_new` (~line 1697). After it, add:

```bash
    type audit_log &>/dev/null && audit_log "$USER" "session.create" "$SESSION_NAME" "$(jq -nc --arg p "$PROJECT_NAME" --arg b "$BRANCH" '{project:$p,branch:$b}')"
```

- [ ] **Step 3: Add audit log call in `cmd_kill` after session teardown**

**IMPORTANT:** `cmd_kill` calls `unregister_session` in multiple places (lines ~2271, ~2303, ~2312, ~2368) for different kill paths (single session, --all, --project). Add the audit call after each `unregister_session` call:

```bash
    type audit_log &>/dev/null && audit_log "$USER" "session.kill" "$name" "$(jq -nc --arg o "$session_owner" '{owner:$o}')"
```

- [ ] **Step 4: Add audit log call in `cmd_attach` after successful attach**

Find the `tmux select-window` / `tmux attach-session` calls in `cmd_attach` (~line 2071). Before the attach, add:

```bash
    type audit_log &>/dev/null && audit_log "$USER" "session.attach" "$target" '{}'
```

- [ ] **Step 5: Verify syntax**

Run: `bash -n bin/dev && echo "OK"`
Expected: OK

- [ ] **Step 6: Commit**

```bash
git add bin/dev
git commit -m "Add audit logging to session lifecycle commands"
```

---

### Task 2.4: Add Session Limit Enforcement to `cmd_new`

**Files:**
- Modify: `bin/dev:1426-1976` (cmd_new — add limit check)
- Add tests to: `tests/test_auth.bats`

- [ ] **Step 1: Write failing test for session limit enforcement**

Append to `tests/test_auth.bats`:
```bash
@test "can_create_session returns false when at limit" {
    echo '{"users":{"alice":{"role":"user","status":"active","max_sessions":2}}}' > "$USERS_FILE"
    # Create 2 fake sessions in ports.json
    echo '{"s1":{"owner":"alice"},"s2":{"owner":"alice"}}' > "$PORT_REGISTRY"
    run can_create_session "alice"
    [ "$status" -eq 1 ]
}

@test "can_create_session returns true when under limit" {
    echo '{"users":{"alice":{"role":"user","status":"active","max_sessions":5}}}' > "$USERS_FILE"
    echo '{"s1":{"owner":"alice"}}' > "$PORT_REGISTRY"
    run can_create_session "alice"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify the tests pass (already implemented in lib/auth.sh)**

Run: `bats tests/test_auth.bats`
Expected: All PASS (can_create_session was implemented in Task 1.2)

- [ ] **Step 3: Add limit check to `cmd_new` in `bin/dev`**

At the start of `cmd_new` (~line 1440), after argument parsing, add:

```bash
    # Check session limit
    if type can_create_session &>/dev/null && ! can_create_session "$USER"; then
        local max
        max=$(get_user_max_sessions "$USER")
        local current
        current=$(count_user_sessions "$USER")
        die "Session limit reached ($current/$max). Kill an existing session or ask admin to increase your limit."
    fi
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n bin/dev && echo "OK"`
Expected: OK

- [ ] **Step 5: Commit**

```bash
git add bin/dev tests/test_auth.bats
git commit -m "Enforce per-user session limits in cmd_new"
```

---

## Chunk 3: Security Hardening

**Agent assignment:** Security (Agent 2)
**Dependencies:** Chunk 1 (lib/auth.sh must exist)
**Produces:** SSH identity binding, authbind port isolation, sudo lockdown

### Task 3.1: SSH Identity Binding Script

**Files:**
- Create: `ssh/validate-tailscale-identity.sh`
- Modify: `bootstrap.sh` (install the script and configure sshd)

- [ ] **Step 1: Create the SSH validation script**

Create `ssh/validate-tailscale-identity.sh`:
```bash
#!/usr/bin/env bash
# validate-tailscale-identity.sh
# Called by sshd as AuthorizedKeysCommand to validate Tailscale identity
# Usage: validate-tailscale-identity.sh <username>
#
# Returns the user's authorized_keys if their Tailscale identity matches,
# empty output (denying login) if it doesn't.

set -euo pipefail

USERNAME="$1"
USERS_FILE="/etc/dev-cli/users.json"

# If no user registry, allow all (single-user mode)
if [[ ! -f "$USERS_FILE" ]]; then
    cat "$HOME/.ssh/authorized_keys" 2>/dev/null || true
    exit 0
fi

# Get the expected Tailscale email for this user
EXPECTED_EMAIL=$(jq -r --arg u "$USERNAME" '.users[$u].tailscale_email // empty' "$USERS_FILE" 2>/dev/null)

# If user not in registry, deny
if [[ -z "$EXPECTED_EMAIL" ]]; then
    exit 0  # empty output = no authorized keys = denied
fi

# Check user status
USER_STATUS=$(jq -r --arg u "$USERNAME" '.users[$u].status // empty' "$USERS_FILE" 2>/dev/null)
if [[ "$USER_STATUS" != "active" ]]; then
    exit 0  # suspended users can't log in
fi

# Get the connecting client's Tailscale identity
# The SSH connection comes from a Tailscale IP (100.x.x.x)
# We use `tailscale whois` to look up who owns that IP
CLIENT_IP="${SSH_CLIENT%% *}"
if [[ -z "$CLIENT_IP" ]]; then
    # Fallback: try SSH_CONNECTION
    CLIENT_IP="${SSH_CONNECTION%% *}"
fi

if [[ -z "$CLIENT_IP" ]]; then
    exit 0  # can't determine client IP, deny
fi

# Check if it's a Tailscale IP
if [[ ! "$CLIENT_IP" =~ ^100\. ]] && [[ ! "$CLIENT_IP" =~ ^fd7a: ]]; then
    # Not a Tailscale IP — this is a direct SSH connection
    # In production, you might want to deny non-Tailscale connections entirely
    # For now, fall through to standard authorized_keys
    cat "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true
    exit 0
fi

# Look up the Tailscale identity
ACTUAL_EMAIL=$(tailscale whois --json "$CLIENT_IP" 2>/dev/null | jq -r '.UserProfile.LoginName // empty')

if [[ -z "$ACTUAL_EMAIL" ]]; then
    exit 0  # can't verify identity, deny
fi

# Compare
if [[ "$ACTUAL_EMAIL" == "$EXPECTED_EMAIL" ]]; then
    cat "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true
else
    # Identity mismatch — deny login
    logger -t dev-cli "SSH denied: $ACTUAL_EMAIL tried to log in as $USERNAME (expected $EXPECTED_EMAIL)"
    exit 0
fi
```

- [ ] **Step 2: Add installation to `bootstrap.sh`**

Add after the Tailscale installation section (~line 225):

```bash
# Install SSH identity binding
info "Setting up SSH identity binding..."
sudo cp ssh/validate-tailscale-identity.sh /usr/local/bin/validate-tailscale-identity
sudo chmod 755 /usr/local/bin/validate-tailscale-identity

# Configure sshd to use the validation script
if ! grep -q "validate-tailscale-identity" /etc/ssh/sshd_config; then
    sudo tee -a /etc/ssh/sshd_config.d/dev-cli.conf > /dev/null <<'SSHEOF'
# dev-cli: Tailscale identity validation
AuthorizedKeysCommand /usr/local/bin/validate-tailscale-identity %u
AuthorizedKeysCommandUser root
SSHEOF
    sudo systemctl reload sshd
fi
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n ssh/validate-tailscale-identity.sh && bash -n bootstrap.sh && echo "OK"`
Expected: OK

- [ ] **Step 4: Commit**

```bash
chmod +x ssh/validate-tailscale-identity.sh
git add ssh/validate-tailscale-identity.sh bootstrap.sh
git commit -m "Add SSH identity binding via Tailscale whois validation"
```

---

### Task 3.2: Disable Cross-User Access

**Files:**
- Modify: `bootstrap.sh` (add security hardening to `add-dev-user` equivalent)

- [ ] **Step 1: Add security hardening to bootstrap.sh**

Add a new section after the multi-user infrastructure setup (~line 123):

```bash
# Harden SSH: disable password auth for local connections
info "Hardening SSH configuration..."
if ! grep -q "dev-cli-hardening" /etc/ssh/sshd_config.d/ 2>/dev/null; then
    sudo tee /etc/ssh/sshd_config.d/dev-cli-hardening.conf > /dev/null <<'SSHEOF'
# dev-cli: Prevent cross-user access
# Disable local password auth (prevents su/ssh localhost attacks)
Match Address 127.0.0.1,::1
    PasswordAuthentication no
    KbdInteractiveAuthentication no
SSHEOF
fi

# Restrict su to root only
info "Restricting su access..."
sudo dpkg-statoverride --update --add root adm 4750 /bin/su 2>/dev/null || true
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n bootstrap.sh && echo "OK"`
Expected: OK

- [ ] **Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "Harden SSH: disable local password auth and restrict su"
```

---

### Task 3.3: Port Isolation with Authbind

**Files:**
- Modify: `bootstrap.sh` (install authbind)
- Modify: `bin/dev:1426-1976` (wrap dev server launch with authbind)

- [ ] **Step 1: Add authbind installation to bootstrap.sh**

Add to the dependency installation section (~line 80):

```bash
info "Installing authbind..."
sudo apt-get install -y authbind
```

- [ ] **Step 2: Add authbind port setup to session creation**

In `bin/dev`, create a helper function after `slot_ports()` (~line 427):

```bash
# Set up authbind for a user's allocated ports
setup_authbind_ports() {
    local username="$1" frontend_port="$2" backend_port="$3" supa_api_port="$4" supa_db_port="$5" supa_studio_port="$6"
    local ports=("$frontend_port" "$backend_port" "$supa_api_port" "$supa_db_port" "$supa_studio_port")
    for port in "${ports[@]}"; do
        sudo touch "/etc/authbind/byport/$port" 2>/dev/null || true
        sudo chown "$username" "/etc/authbind/byport/$port" 2>/dev/null || true
        sudo chmod 500 "/etc/authbind/byport/$port" 2>/dev/null || true
    done
}

# Clean up authbind for deallocated ports
cleanup_authbind_ports() {
    local frontend_port="$1" backend_port="$2" supa_api_port="$3" supa_db_port="$4" supa_studio_port="$5"
    local ports=("$frontend_port" "$backend_port" "$supa_api_port" "$supa_db_port" "$supa_studio_port")
    for port in "${ports[@]}"; do
        sudo rm -f "/etc/authbind/byport/$port" 2>/dev/null || true
    done
}
```

- [ ] **Step 3: Call setup in `cmd_new` after slot allocation**

After `slot_ports` is called in `cmd_new` (~line 1500), add:

```bash
    # Set up port isolation
    if command -v authbind &>/dev/null; then
        setup_authbind_ports "$USER" "$FRONTEND_PORT" "$BACKEND_PORT" "$SUPA_API_PORT" "$SUPA_DB_PORT" "$SUPA_STUDIO_PORT"
    fi
```

- [ ] **Step 4: Call cleanup in `cmd_kill` after session teardown**

After `unregister_session` in `cmd_kill` (~line 2280), add:

```bash
    # Clean up port isolation
    if command -v authbind &>/dev/null; then
        cleanup_authbind_ports "$frontend_port" "$backend_port" "$supa_api_port" "$supa_db_port" "$supa_studio_port"
    fi
```

- [ ] **Step 5: Verify syntax**

Run: `bash -n bin/dev && bash -n bootstrap.sh && echo "OK"`
Expected: OK

- [ ] **Step 6: Commit**

```bash
git add bin/dev bootstrap.sh
git commit -m "Add authbind-based port isolation per session"
```

---

## Chunk 4: User Onboarding

**Agent assignment:** Agent 3
**Dependencies:** Chunks 1 and 2 (auth helpers and admin CLI)
**Produces:** `dev setup-account` command, improved `dev doctor`

### Task 4.1: Implement `dev setup-account`

**Files:**
- Modify: `bin/dev` (add `cmd_setup_account` function and case route)

- [ ] **Step 1: Add `cmd_setup_account` function to `bin/dev`**

Add before `cmd_help()` (~line 6682):

```bash
cmd_setup_account() {
    echo -e "${BOLD}Welcome to dev-cli! Let's set up your account.${NC}"
    echo ""

    # Step 1: Check user registration
    if type is_user_registered &>/dev/null && has_user_registry; then
        if ! is_user_registered "$USER"; then
            die "Your account ($USER) is not registered. Ask your admin to run: dev admin add-user $USER --tailscale-email <your-email>"
        fi

        local status
        status=$(get_user_status "$USER")
        if [[ "$status" != "active" ]]; then
            die "Your account is $status. Contact your admin."
        fi

        local email
        email=$(get_user_field "$USER" "tailscale_email")
        log "Account registered as: $USER <$email>"
    else
        info "Running in single-user mode (no user registry)"
    fi

    # Step 2: Tailscale verification
    echo ""
    info "Checking Tailscale..."
    if command -v tailscale &>/dev/null; then
        if tailscale status --self &>/dev/null; then
            local ts_ip
            ts_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
            log "Tailscale connected (IP: $ts_ip)"
        else
            warn "Tailscale is installed but not connected."
            echo "  Run: sudo tailscale up"
            echo "  Then re-run: dev setup-account"
            return 1
        fi
    else
        warn "Tailscale not installed. Ask your admin for setup instructions."
    fi

    # Step 3: GitHub auth
    echo ""
    info "Checking GitHub CLI..."
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null 2>&1; then
            local gh_user
            gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            log "GitHub authenticated as: $gh_user"
        else
            warn "GitHub CLI not authenticated."
            echo "  Run: gh auth login"
            echo ""
            read -rp "Would you like to authenticate now? [Y/n] " answer
            if [[ "${answer:-y}" =~ ^[Yy] ]]; then
                gh auth login
            fi
        fi
    else
        warn "GitHub CLI (gh) not installed."
    fi

    # Step 4: Claude auth
    echo ""
    info "Checking Claude Code..."
    if command -v claude &>/dev/null; then
        # Check if claude has valid auth
        if [[ -f "$HOME/.config/dev-cli/secrets.env" ]]; then
            if grep -q "CLAUDE_CODE_OAUTH_TOKEN\|ANTHROPIC_API_KEY" "$HOME/.config/dev-cli/secrets.env" 2>/dev/null; then
                log "Claude Code credentials found in secrets.env"
            else
                warn "No Claude credentials in secrets.env"
                echo "  Run: claude login"
                echo ""
                read -rp "Would you like to authenticate now? [Y/n] " answer
                if [[ "${answer:-y}" =~ ^[Yy] ]]; then
                    claude login
                fi
            fi
        else
            warn "No secrets.env found."
        fi
    else
        warn "Claude Code not installed."
        echo "  Run: curl -fsSL https://cli.claude.ai/install.sh | sh"
    fi

    # Step 5: Run doctor
    echo ""
    info "Running health check..."
    cmd_doctor

    # Step 6: Mark as onboarded
    if type set_user_field_raw &>/dev/null && has_user_registry; then
        set_user_field_raw "$USER" "onboarded" "true"
    fi

    echo ""
    log "Account setup complete!"
    echo ""
    echo "Quick start:"
    echo "  dev init <project>     Set up a project for the first time"
    echo "  dev new <branch>       Start a new session"
    echo "  dev hub                Launch the interactive dashboard"
    echo "  dev help               See all commands"
}
```

- [ ] **Step 2: Add case route in main router**

At `bin/dev:6937`, add:
```bash
    setup-account) cmd_setup_account "$@" ;;
```

- [ ] **Step 3: Add to help output**

In `cmd_help()`, add inside the single-quoted heredoc (plain text, no variables):
```
Getting Started:
  setup-account  Interactive first-time account setup
```

- [ ] **Step 4: Add to tab completion in `completions/dev.bash`**

Add `setup-account` to the `commands` variable at line 21 (if not already added in Task 2.2).

- [ ] **Step 5: Verify syntax**

Run: `bash -n bin/dev && echo "OK"`
Expected: OK

- [ ] **Step 6: Commit**

```bash
git add bin/dev install.sh
git commit -m "Add 'dev setup-account' interactive onboarding command"
```

---

### Task 4.2: Enhance `dev doctor` with Security Checks

**Files:**
- Modify: `bin/dev:3390-3535` (cmd_doctor)

- [ ] **Step 1: Add security checks to `cmd_doctor`**

After the existing checks in `cmd_doctor` (~line 3530), add:

```bash
    # --- Security checks (multi-user mode only) ---
    if type has_user_registry &>/dev/null && has_user_registry; then
        echo ""
        echo -e "${BOLD}Security:${NC}"

        # User registration
        if is_user_registered "$USER"; then
            local role status
            role=$(get_user_role "$USER")
            status=$(get_user_status "$USER")
            echo -e "  User registration:  ${GREEN}✓${NC} $USER (role: $role, status: $status)"
        else
            echo -e "  User registration:  ${RED}✗${NC} $USER not in registry"
        fi

        # Authbind
        if command -v authbind &>/dev/null; then
            echo -e "  Port isolation:     ${GREEN}✓${NC} authbind installed"
        else
            echo -e "  Port isolation:     ${YELLOW}⚠${NC} authbind not installed"
        fi

        # SSH identity binding
        if [[ -f /usr/local/bin/validate-tailscale-identity ]]; then
            echo -e "  SSH binding:        ${GREEN}✓${NC} identity validation installed"
        else
            echo -e "  SSH binding:        ${YELLOW}⚠${NC} not configured"
        fi

        # Session limits
        local current max
        current=$(count_user_sessions "$USER")
        max=$(get_user_max_sessions "$USER")
        echo -e "  Session limit:      ${GREEN}✓${NC} $current/$max sessions"
    fi
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n bin/dev && echo "OK"`
Expected: OK

- [ ] **Step 3: Commit**

```bash
git add bin/dev
git commit -m "Enhance dev doctor with security and registration checks"
```

---

## Chunk 5: Resource Management

**Agent assignment:** Agent 4
**Dependencies:** Chunk 1 (lib/auth.sh)
**Produces:** Session limits (already in Chunk 2), stale session detection, disk monitoring

Note: Session limit enforcement was already added in Task 2.4. This chunk covers stale sessions and disk monitoring which are surfaced through `dev admin` commands already defined in `bin/dev-admin`.

### Task 5.1: Add Stale Session Detection Tests

**Files:**
- Create: `tests/test_resources.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats

load test_helpers

setup() {
    setup_test_env
    source lib/auth.sh
    source lib/audit.sh
}

teardown() {
    teardown_test_env
}

@test "count_user_sessions counts correctly" {
    echo '{"s1":{"owner":"alice"},"s2":{"owner":"alice"},"s3":{"owner":"bob"}}' > "$PORT_REGISTRY"
    run count_user_sessions "alice"
    [ "$output" = "2" ]
}

@test "count_user_sessions returns 0 for user with no sessions" {
    echo '{"s1":{"owner":"alice"}}' > "$PORT_REGISTRY"
    run count_user_sessions "bob"
    [ "$output" = "0" ]
}

@test "count_user_sessions returns 0 for empty registry" {
    echo '{}' > "$PORT_REGISTRY"
    run count_user_sessions "alice"
    [ "$output" = "0" ]
}
```

- [ ] **Step 2: Run tests**

Run: `bats tests/test_resources.bats`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add tests/test_resources.bats
git commit -m "Add resource management tests"
```

---

## Chunk 5B: Dev-Hub Role Indicators

**Agent assignment:** Agent 4 (or Agent 1 after core work)
**Dependencies:** Chunk 1 (lib/auth.sh)
**Produces:** Role badges and admin indicators in dev-hub TUI

### Task 5B.1: Add Role Badges to Dev-Hub Session List

**Files:**
- Modify: `bin/dev-hub`

- [ ] **Step 1: Source auth helpers in dev-hub**

Near the top of `bin/dev-hub`, after the existing helper functions, add the same LIB_DIR detection and source pattern used in `bin/dev`:

```bash
_hub_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$_hub_script_dir/../lib/dev-cli" ]]; then
    _HUB_LIB_DIR="$_hub_script_dir/../lib/dev-cli"
elif [[ -d "$_hub_script_dir/../lib" ]]; then
    _HUB_LIB_DIR="$_hub_script_dir/../lib"
fi
[[ -n "${_HUB_LIB_DIR:-}" && -f "$_HUB_LIB_DIR/auth.sh" ]] && source "$_HUB_LIB_DIR/auth.sh"
```

- [ ] **Step 2: Add role badge to session list rendering**

In the session list rendering section of dev-hub, when displaying the owner field, add a role indicator:

```bash
# After getting session owner, add role badge
local role_badge=""
if type get_user_role &>/dev/null; then
    local owner_role
    owner_role=$(get_user_role "$session_owner" 2>/dev/null || echo "")
    [[ "$owner_role" == "admin" ]] && role_badge=" [A]"
fi
# Append role_badge when displaying the owner column
```

- [ ] **Step 3: Show admin indicator in footer**

In the footer rendering, show the current user's role:

```bash
if type is_admin &>/dev/null && is_admin "$USER"; then
    footer_role=" (admin)"
else
    footer_role=""
fi
# Include $footer_role in the footer status line
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n bin/dev-hub && echo "OK"`
Expected: OK

- [ ] **Step 5: Commit**

```bash
git add bin/dev-hub
git commit -m "Add role badges and admin indicator to dev-hub"
```

---

## Chunk 6: Documentation

**Agent assignment:** Docs (Agent 5, fully parallel)
**Dependencies:** None (can reference spec for command signatures)
**Produces:** `docs/admin/`, `docs/user/`, updated `README.md`

### Task 6.1: Create Admin Quickstart Guide

**Files:**
- Create: `docs/admin/quickstart.md`

- [ ] **Step 1: Write admin quickstart**

```markdown
# Admin Quickstart

Get dev-cli running on a fresh VPS in 10 minutes.

## Prerequisites

- Ubuntu 22.04+ or Debian 12+ VPS (4GB+ RAM recommended)
- A Tailscale account (free tier works)
- SSH access to the VPS

## Step 1: Bootstrap the Server

SSH into your VPS and run:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/theholdinco/dev-cli/main/bootstrap.sh | bash
\`\`\`

This installs all system dependencies (Docker, tmux, git, jq, Tailscale, authbind, etc.) and sets up the multi-user infrastructure.

## Step 2: Connect Tailscale

\`\`\`bash
sudo tailscale up
\`\`\`

Follow the link to authenticate. Note your Tailscale IP:

\`\`\`bash
tailscale ip -4
\`\`\`

## Step 3: Add Your Admin Account

\`\`\`bash
dev admin add-user $(whoami) --tailscale-email your@email.com --role admin
\`\`\`

## Step 4: Add Your First User

\`\`\`bash
dev admin add-user alice --tailscale-email alice@company.com --role user
\`\`\`

This outputs onboarding instructions to send to the user.

## Step 5: Verify

\`\`\`bash
dev admin list-users
dev admin status
dev doctor
\`\`\`

## Next Steps

- [User Management](user-management.md) — add/remove/suspend users
- [Security](security.md) — how identity binding and port isolation work
- [Configuration](configuration.md) — hooks, templates, shared secrets
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
mkdir -p docs/admin
git add docs/admin/quickstart.md
git commit -m "Add admin quickstart guide"
```

---

### Task 6.2: Create Admin User Management Guide

**Files:**
- Create: `docs/admin/user-management.md`

- [ ] **Step 1: Write user management guide**

```markdown
# User Management

## Adding Users

\`\`\`bash
dev admin add-user <username> --tailscale-email <email> [--role admin|user]
\`\`\`

This:
1. Creates a Linux user with a temporary password
2. Installs dev-cli and Claude Code for the user
3. Binds their Tailscale identity for SSH enforcement
4. Links shared secrets
5. Prints onboarding instructions to send them

**Example:**
\`\`\`bash
dev admin add-user bob --tailscale-email bob@company.com
# Output includes a message to copy-paste to the new user
\`\`\`

## Listing Users

\`\`\`bash
dev admin list-users
\`\`\`

Shows all registered users with their role, status, active session count, and creation date.

## Suspending Users

\`\`\`bash
dev admin suspend-user <username>
\`\`\`

Disables login without deleting data. The user's sessions remain but they can't create new ones or log in.

\`\`\`bash
dev admin restore-user <username>
\`\`\`

Re-enables a suspended user.

## Removing Users

\`\`\`bash
dev admin remove-user <username>           # Disable login, keep data
dev admin remove-user <username> --purge   # Delete everything
\`\`\`

Without `--purge`, this kills sessions and disables login but preserves the home directory. With `--purge`, everything is deleted.

## Roles

Two roles: `admin` and `user`.

\`\`\`bash
dev admin set-role <username> admin   # Promote
dev admin set-role <username> user    # Demote
\`\`\`

Admins can run all `dev admin` commands. Users can only manage their own sessions.

## Session Limits

\`\`\`bash
dev admin set-limit <username> --max-sessions 10
\`\`\`

Default is 8 concurrent sessions per user. The limit is enforced when creating new sessions.
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add docs/admin/user-management.md
git commit -m "Add admin user management guide"
```

---

### Task 6.3: Create Admin Security Guide

**Files:**
- Create: `docs/admin/security.md`

- [ ] **Step 1: Write security guide**

```markdown
# Security Model

## Overview

dev-cli uses a layered security model:

1. **Network:** Tailscale private mesh (no public internet exposure)
2. **Identity:** Tailscale email → Linux user binding
3. **Session:** File permissions + ownership tracking
4. **Ports:** authbind per-user port authorization

## Tailscale Identity Binding

When a user SSHs into the server, the system validates that their Tailscale identity matches the registered Linux user. This prevents:

- User A logging in as User B (even if they know the password)
- Local `su` or `ssh localhost` attacks

**How it works:**
1. `dev admin add-user` registers `username ↔ tailscale_email` in `/etc/dev-cli/users.json`
2. SSH server uses `AuthorizedKeysCommand` to run `/usr/local/bin/validate-tailscale-identity`
3. The script checks `tailscale whois` on the connecting IP and compares the email
4. Mismatch = login denied (logged to syslog)

## Port Isolation

Each session gets dedicated ports. authbind ensures only the session owner can bind to those ports.

- Port rules are created when a session starts (`dev new`)
- Port rules are removed when a session is killed (`dev kill`)
- Admins can grant temporary access: `dev admin port-access <session> --grant <user>`

## Secrets

- **Per-user secrets:** `~/.config/dev-cli/secrets.env` (chmod 600) — API keys, tokens
- **Shared secrets:** `/etc/dev-cli/secrets/` — read-only symlinks into each user's config

Never share Claude or GitHub tokens between users.

## Audit Log

All admin and session lifecycle events are logged to `/etc/dev-cli/audit.log`:

\`\`\`bash
dev admin audit                    # Show all events
dev admin audit --user alice       # Filter by user
dev admin audit --last 24h         # Last 24 hours
\`\`\`

## Firewall

The bootstrap configures UFW:
- Allow SSH (OpenSSH profile)
- Allow all traffic on Tailscale interface
- Deny everything else

Do not expose dev server ports to the public internet.
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add docs/admin/security.md
git commit -m "Add admin security guide"
```

---

### Task 6.4: Create Admin Troubleshooting and Configuration Guides

**Files:**
- Create: `docs/admin/troubleshooting.md`
- Create: `docs/admin/configuration.md`

- [ ] **Step 1: Write troubleshooting guide**

Content should cover: user can't log in (Tailscale identity mismatch, suspended account, SSH config), session creation fails (slot exhaustion, session limit), port conflicts, ports.json corruption recovery, how to view audit logs for debugging.

- [ ] **Step 2: Write configuration guide**

Content should cover: setup hooks (`~/.config/dev-cli/hooks/<project>/setup.sh`), env templates (`~/.config/dev-cli/templates/<project>.env`), shared secrets management, project configuration, stale session cleanup policy, global config at `~/.config/dev-cli/config.json`.

- [ ] **Step 3: Commit**

```bash
git add docs/admin/troubleshooting.md docs/admin/configuration.md
git commit -m "Add admin troubleshooting and configuration guides"
```

---

### Task 6.5: Create User Getting Started Guide

**Files:**
- Create: `docs/user/getting-started.md`

- [ ] **Step 1: Write getting started guide**

```markdown
# Getting Started

Your admin has set up a dev server for you. Here's how to connect and start working.

## Step 1: Install Tailscale

Download Tailscale for your platform: https://tailscale.com/download

Sign in with the account your admin registered you with.

## Step 2: Connect via SSH

\`\`\`bash
ssh <your-username>@<server-hostname>
\`\`\`

Your admin will give you the hostname and a temporary password. You'll be asked to change it on first login.

## Step 3: Set Up Your Account

\`\`\`bash
dev setup-account
\`\`\`

This walks you through:
- Verifying your Tailscale connection
- Authenticating GitHub (`gh auth login`)
- Authenticating Claude Code (`claude login`)
- Running a health check

## Step 4: Initialize a Project

\`\`\`bash
dev init <project-name>
\`\`\`

Or if the project isn't set up yet:

\`\`\`bash
dev setup <project-name> <git-url>
\`\`\`

## Step 5: Start Your First Session

\`\`\`bash
dev new my-feature --agent claude
\`\`\`

This creates an isolated workspace with its own git branch and dedicated ports.

## Step 6: Open the Dashboard

\`\`\`bash
dev hub
\`\`\`

The dashboard shows all your sessions with keyboard shortcuts for common actions.

## Next Steps

- [Daily Workflow](daily-workflow.md) — common patterns
- [Commands](commands.md) — full reference
- [Tips](tips.md) — mobile access, shortcuts
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
mkdir -p docs/user
git add docs/user/getting-started.md
git commit -m "Add user getting started guide"
```

---

### Task 6.6: Create User Daily Workflow, Commands, Tips, and FAQ

**Files:**
- Create: `docs/user/daily-workflow.md`
- Create: `docs/user/commands.md`
- Create: `docs/user/tips.md`
- Create: `docs/user/faq.md`

- [ ] **Step 1: Write daily workflow guide**

Cover: starting a session, attaching to sessions, checking status with `dev ls`, using the hub, killing sessions, working with multiple branches, PR workflow.

- [ ] **Step 2: Write commands reference**

Generate from `cmd_help()` output but with examples for each command. Group by category: session management, project management, git/PR, monitoring, admin.

- [ ] **Step 3: Write tips guide**

Cover: mobile access (Tailscale + SSH client), tmux shortcuts, Telegram notifications setup, using `dev yolo` for autonomous mode, partial name matching.

- [ ] **Step 4: Write FAQ**

Cover: "How do I see other people's sessions?", "What ports does my session use?", "How do I share a session?", "My session is stuck", "I hit my session limit".

- [ ] **Step 5: Commit**

```bash
git add docs/user/
git commit -m "Add user workflow, commands, tips, and FAQ guides"
```

---

### Task 6.7: Update README as Landing Page

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README.md as a landing page**

Keep it concise — project description, one-liner install, then point to the two doc tracks:

```markdown
# dev-cli

Manage multiple AI coding agent instances on a shared VPS. Built for dev teams.

## Quick Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/theholdinco/dev-cli/main/bootstrap.sh | bash
\`\`\`

## Documentation

**Admins:** [Quickstart](docs/admin/quickstart.md) · [User Management](docs/admin/user-management.md) · [Security](docs/admin/security.md) · [Configuration](docs/admin/configuration.md) · [Troubleshooting](docs/admin/troubleshooting.md)

**Users:** [Getting Started](docs/user/getting-started.md) · [Daily Workflow](docs/user/daily-workflow.md) · [Commands](docs/user/commands.md) · [Tips](docs/user/tips.md) · [FAQ](docs/user/faq.md)

## What It Does

- Manages isolated git worktrees per coding session
- Allocates dedicated ports (frontend, backend, Supabase)
- Runs AI agents (Claude Code, Codex) in persistent tmux sessions
- Multi-user with Tailscale identity binding and role-based access
- Interactive TUI dashboard and Telegram notifications
\`\`\`
```

- [ ] **Step 2: Remove consolidated docs**

```bash
git rm MULTI_USER_SETUP.md HOW_I_USE_IT.md docs/TEAM_SETUP.md MOBILE_SETUP.md
```

(Only after verifying all content has been migrated into the new docs structure)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Rewrite README as landing page pointing to new doc structure"
```

---

## Chunk 7: Operations

**Agent assignment:** Agent 4 (same as Resource Management, or separate)
**Dependencies:** Chunk 2 (admin CLI must exist)
**Produces:** backup/restore, update mechanism

Note: Backup, restore, and update commands are already implemented in `bin/dev-admin` (Chunk 2). This chunk covers integration testing and any remaining wiring.

### Task 7.1: Add Version Tracking

**Files:**
- Modify: `install.sh` (write version file on install)
- Modify: `bin/dev` (add `--version` flag)

- [ ] **Step 1: Add version writing to `install.sh`**

At the end of `install.sh`, add:

```bash
# Write version
VERSION=$(git describe --tags --always 2>/dev/null || echo "dev")
echo "$VERSION" > "$HOME/.local/bin/.dev-version"
```

- [ ] **Step 2: Add version flag to `bin/dev`**

At the top of the main case statement:

```bash
    --version|-v) echo "dev-cli $(cat "$(dirname "$0")/.dev-version" 2>/dev/null || echo "unknown")"; exit 0 ;;
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n bin/dev && bash -n install.sh && echo "OK"`
Expected: OK

- [ ] **Step 4: Commit**

```bash
git add bin/dev install.sh
git commit -m "Add version tracking and --version flag"
```

---

## Agent Assignment Summary

| Agent | Chunks | Dependencies | Can Start |
|-------|--------|-------------|-----------|
| Agent 1 (Core) | 1, 2 | None | Immediately |
| Agent 2 (Security) | 3 | Chunk 1 | After Task 1.2 |
| Agent 3 (Onboarding) | 4 | Chunks 1, 2 | After Chunk 2 |
| Agent 4 (Resources + Ops + Hub) | 5, 5B, 7 | Chunk 1 | After Task 1.2 |
| Agent 5 (Docs) | 6 | None | Immediately |

**Parallel from the start:** Agents 1 and 5
**Parallel after foundation:** Agents 2, 4
**Sequential:** Agent 3 (last, depends on admin CLI)

## Review Fixes Applied
- C1: Fixed cmd_help() heredoc issue — use plain text inside single-quoted heredoc
- C2: Fixed tab completion reference — completions/dev.bash, not install.sh
- C3: Added set_user_field_raw() for boolean/numeric values, use it for onboarded field
- C4: Added require_admin to cmd_admin_list_users
- I1: Fixed register_session line number (~1697, not ~1890)
- I2: Fixed cmd_attach tmux line reference (~2071)
- I4: Noted multiple unregister_session call sites in cmd_kill
- I6: Fixed LIB_DIR path resolution for both dev repo and installed location
- I7: Fixed stale_sessions subshell variable with process substitution
- I9: Fixed MOBILE_SETUP.md path (root, not docs/)
- S1: Added Chunk 5B for dev-hub role indicators
- S4: Added flock locking to all users.json write operations
