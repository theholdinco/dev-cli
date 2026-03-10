#!/usr/bin/env bats

@test "bash syntax check bin/dev" {
    bash -n bin/dev
}

@test "bash syntax check bin/dev-hub" {
    bash -n bin/dev-hub
}
