#!/usr/bin/env bats
# tests/remove-graph.bats

setup() {
    load 'test_helper/common'

    # Create test config directory
    export CONFIG_DIR="$BATS_TMPDIR/config-$$"
    mkdir -p "$CONFIG_DIR/graphs"
    mkdir -p "$CONFIG_DIR/logs"

    # Create LaunchAgents directory
    export LAUNCH_AGENTS="$BATS_TMPDIR/LaunchAgents-$$"
    mkdir -p "$LAUNCH_AGENTS"

    # Point scripts to test config via HOME
    export HOME="$BATS_TMPDIR/home-$$"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/Library"
    ln -s "$CONFIG_DIR" "$HOME/.config/logseq-git-sync"
    ln -s "$LAUNCH_AGENTS" "$HOME/Library/LaunchAgents"

    # Create a test graph config
    cat > "$CONFIG_DIR/graphs/testgraph.conf" << 'EOF'
REPO_PATH="/tmp/test-repo"
REMOTE="origin"
BRANCH="main"
EOF

    # Create launchd plists for the test graph
    touch "$LAUNCH_AGENTS/com.logseq-sync.watcher.testgraph.plist"
    touch "$LAUNCH_AGENTS/com.logseq-sync.commit.testgraph.plist"
    touch "$LAUNCH_AGENTS/com.logseq-sync.fetch.testgraph.plist"

    # Create temp files
    touch "/tmp/logseq-sync-trigger-testgraph"
    touch "/tmp/logseq-sync-lastchange-testgraph"

    # Create log files
    touch "$CONFIG_DIR/logs/watcher-testgraph.out"
    touch "$CONFIG_DIR/logs/watcher-testgraph.err"
    touch "$CONFIG_DIR/logs/commit-testgraph.out"
    touch "$CONFIG_DIR/logs/commit-testgraph.err"
    touch "$CONFIG_DIR/logs/fetch-testgraph.out"
    touch "$CONFIG_DIR/logs/fetch-testgraph.err"
}

teardown() {
    rm -rf "$CONFIG_DIR"
    rm -rf "$HOME"
    rm -rf "$LAUNCH_AGENTS"
    rm -f "/tmp/logseq-sync-trigger-testgraph"
    rm -f "/tmp/logseq-sync-lastchange-testgraph"
}

# ============================================
# remove-graph with no arguments
# ============================================

@test "remove-graph with no arguments shows usage" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "usage:" ]]
}

# ============================================
# remove-graph with non-existent graph
# ============================================

@test "remove-graph with non-existent graph fails" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph nonexistent --force

    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "remove-graph with non-existent graph lists available graphs" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph nonexistent --force

    [ "$status" -eq 1 ]
    [[ "$output" =~ "testgraph" ]]
}

# ============================================
# remove-graph --force (skip confirmation)
# ============================================

@test "remove-graph --force removes config file" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "$CONFIG_DIR/graphs/testgraph.conf" ]
}

@test "remove-graph --force removes watcher plist" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "$LAUNCH_AGENTS/com.logseq-sync.watcher.testgraph.plist" ]
}

@test "remove-graph --force removes commit plist" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "$LAUNCH_AGENTS/com.logseq-sync.commit.testgraph.plist" ]
}

@test "remove-graph --force removes fetch plist" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "$LAUNCH_AGENTS/com.logseq-sync.fetch.testgraph.plist" ]
}

@test "remove-graph --force removes trigger file" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "/tmp/logseq-sync-trigger-testgraph" ]
}

@test "remove-graph --force removes lastchange file" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "/tmp/logseq-sync-lastchange-testgraph" ]
}

@test "remove-graph --force removes log files" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [ ! -f "$CONFIG_DIR/logs/watcher-testgraph.out" ]
    [ ! -f "$CONFIG_DIR/logs/watcher-testgraph.err" ]
    [ ! -f "$CONFIG_DIR/logs/commit-testgraph.out" ]
    [ ! -f "$CONFIG_DIR/logs/commit-testgraph.err" ]
    [ ! -f "$CONFIG_DIR/logs/fetch-testgraph.out" ]
    [ ! -f "$CONFIG_DIR/logs/fetch-testgraph.err" ]
}

@test "remove-graph --force prints success message" {
    run "$BATS_TEST_DIRNAME/../scripts/logseq-sync" remove-graph testgraph --force

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Removed" ]] || [[ "$output" =~ "removed" ]]
}

# ============================================
# remove-graph without --force (confirmation)
# ============================================

@test "remove-graph without --force and 'n' input aborts" {
    run bash -c "export HOME='$HOME'; echo 'n' | $BATS_TEST_DIRNAME/../scripts/logseq-sync remove-graph testgraph"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Aborted" ]]
    [ -f "$CONFIG_DIR/graphs/testgraph.conf" ]
}

@test "remove-graph without --force and 'y' input proceeds" {
    run bash -c "export HOME='$HOME'; echo 'y' | $BATS_TEST_DIRNAME/../scripts/logseq-sync remove-graph testgraph"

    [ "$status" -eq 0 ]
    [ ! -f "$CONFIG_DIR/graphs/testgraph.conf" ]
}

@test "remove-graph without --force shows confirmation prompt" {
    run bash -c "export HOME='$HOME'; echo 'n' | $BATS_TEST_DIRNAME/../scripts/logseq-sync remove-graph testgraph"

    [[ "$output" =~ "Continue" ]] || [[ "$output" =~ "continue" ]]
}

@test "remove-graph without --force mentions files won't be deleted" {
    run bash -c "export HOME='$HOME'; echo 'n' | $BATS_TEST_DIRNAME/../scripts/logseq-sync remove-graph testgraph"

    [[ "$output" =~ "NOT be deleted" ]] || [[ "$output" =~ "will NOT" ]]
}
