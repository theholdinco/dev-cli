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
