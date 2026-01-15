#!/usr/bin/env bats
# tests/config.bats

setup() {
    load 'test_helper/common'

    # Create test config directory
    export CONFIG_DIR="$BATS_TMPDIR/config-$$"
    mkdir -p "$CONFIG_DIR/graphs"
    mkdir -p "$CONFIG_DIR/logs"

    # Create global config
    cat > "$CONFIG_DIR/config" << 'EOF'
QUIET_PERIOD=30
FETCH_INTERVAL=300
NOTIFY_ON_PUSH=true
EOF

    # Create a test graph config
    cat > "$CONFIG_DIR/graphs/testgraph.conf" << 'EOF'
REPO_PATH="/tmp/test-repo"
REMOTE="origin"
BRANCH="main"
QUIET_PERIOD=60
EOF

    # Point scripts to test config
    export HOME="$BATS_TMPDIR/home-$$"
    mkdir -p "$HOME/.config"
    ln -s "$CONFIG_DIR" "$HOME/.config/logseq-git-sync"
}

teardown() {
    rm -rf "$CONFIG_DIR"
    rm -rf "$HOME"
}

# ============================================
# config (no args) - show global + list graphs
# ============================================

@test "config shows global config" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config

    [ "$status" -eq 0 ]
    [[ "$output" =~ "QUIET_PERIOD=30" ]]
    [[ "$output" =~ "FETCH_INTERVAL=300" ]]
}

@test "config lists available graphs" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config

    [ "$status" -eq 0 ]
    [[ "$output" =~ "testgraph" ]]
}

@test "config with no global config shows defaults" {
    rm "$CONFIG_DIR/config"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config

    [ "$status" -eq 0 ]
    [[ "$output" =~ "defaults" ]] || [[ "$output" =~ "no config file" ]]
}

# ============================================
# config show
# ============================================

@test "config show works same as config" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config show

    [ "$status" -eq 0 ]
    [[ "$output" =~ "QUIET_PERIOD=30" ]]
}

@test "config show --graph shows graph config" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config show --graph testgraph

    [ "$status" -eq 0 ]
    [[ "$output" =~ "REPO_PATH=" ]]
    [[ "$output" =~ "QUIET_PERIOD=60" ]]
}

@test "config show --graph with unknown graph fails" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config show --graph nonexistent

    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

# ============================================
# config get
# ============================================

@test "config get returns raw value" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get QUIET_PERIOD

    [ "$status" -eq 0 ]
    [ "$output" = "30" ]
}

@test "config get --graph returns graph value" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get QUIET_PERIOD --graph testgraph

    [ "$status" -eq 0 ]
    [ "$output" = "60" ]
}

@test "config get with unknown key exits 1" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get NONEXISTENT_KEY

    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "config get --graph with unknown graph fails" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get QUIET_PERIOD --graph nonexistent

    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

# ============================================
# config set
# ============================================

@test "config set updates existing value" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config set QUIET_PERIOD 45

    [ "$status" -eq 0 ]

    # Verify it was set
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get QUIET_PERIOD
    [ "$output" = "45" ]
}

@test "config set adds new key" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config set NEW_KEY newvalue

    [ "$status" -eq 0 ]

    # Verify it was added
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get NEW_KEY
    [ "$output" = "newvalue" ]
}

@test "config set --graph updates graph config" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config set QUIET_PERIOD 90 --graph testgraph

    [ "$status" -eq 0 ]

    # Verify it was set
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config get QUIET_PERIOD --graph testgraph
    [ "$output" = "90" ]
}

@test "config set --graph with unknown graph fails" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config set QUIET_PERIOD 90 --graph nonexistent

    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "config set creates global config from template if missing" {
    rm "$CONFIG_DIR/config"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config set QUIET_PERIOD 45

    [ "$status" -eq 0 ]
    [ -f "$CONFIG_DIR/config" ]
}

# ============================================
# config edit
# ============================================

@test "config edit opens editor" {
    # Create mock editor script
    cat > "$BATS_TMPDIR/mock-editor" << EOF
#!/bin/bash
touch "$BATS_TMPDIR/editor-called"
EOF
    chmod +x "$BATS_TMPDIR/mock-editor"
    export EDITOR="$BATS_TMPDIR/mock-editor"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config edit

    [ "$status" -eq 0 ]
    [ -f "$BATS_TMPDIR/editor-called" ]
}

@test "config edit --graph opens graph config" {
    # Create mock editor script
    cat > "$BATS_TMPDIR/mock-editor-graph" << EOF
#!/bin/bash
touch "$BATS_TMPDIR/editor-called-graph"
EOF
    chmod +x "$BATS_TMPDIR/mock-editor-graph"
    export EDITOR="$BATS_TMPDIR/mock-editor-graph"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config edit --graph testgraph

    [ "$status" -eq 0 ]
    [ -f "$BATS_TMPDIR/editor-called-graph" ]
}

@test "config edit creates global config from template if missing" {
    rm "$CONFIG_DIR/config"
    export EDITOR="cat"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config edit

    [ "$status" -eq 0 ]
    [ -f "$CONFIG_DIR/config" ]
}

@test "config edit --graph with unknown graph fails" {
    export EDITOR="cat"

    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" config edit --graph nonexistent

    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}
