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
