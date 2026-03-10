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

# --- Session limit tests ---

@test "can_create_session returns false when at limit" {
    echo '{"users":{"alice":{"role":"user","status":"active","max_sessions":2}}}' > "$USERS_FILE"
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
