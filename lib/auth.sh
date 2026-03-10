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
        return 0  # single-user mode: no registry
    fi
    # Empty registry = setup mode, treat everyone as admin
    local user_count
    user_count=$(jq '.users | length' "$USERS_FILE" 2>/dev/null || echo "0")
    if [[ "$user_count" -eq 0 ]]; then
        return 0
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
    [[ -f "$USERS_FILE" ]] || echo '{"users":{}}' > "$USERS_FILE"
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
