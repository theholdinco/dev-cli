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
