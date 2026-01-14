#!/usr/bin/env bats
# tests/integration.bats

setup() {
    load 'test_helper/common'

    export CONFIG_DIR="$BATS_TMPDIR/config-$$"
    export LAUNCH_AGENTS="$BATS_TMPDIR/launch-$$"

    mkdir -p "$CONFIG_DIR/graphs" "$CONFIG_DIR/logs" "$LAUNCH_AGENTS"

    # Create test repo
    export TEST_REPO="$BATS_TMPDIR/test-repo-$$"
    mkdir -p "$TEST_REPO"/{journals,pages}
    cd "$TEST_REPO"
    git init
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "- initial" > journals/2026-01-01.md
    git add .
    git commit -m "initial"
}

teardown() {
    rm -rf "$CONFIG_DIR" "$LAUNCH_AGENTS" "$TEST_REPO"
}

@test "full sync cycle works" {
    # Create graph config manually
    cat > "$CONFIG_DIR/graphs/test.conf" << EOF
REPO_PATH="$TEST_REPO"
REMOTE="origin"
BRANCH="main"
EOF

    # Source commit script (which sources notify)
    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-commit.sh"

    # Make a change
    cd "$TEST_REPO"
    echo "- new entry" >> journals/2026-01-01.md

    # Commit
    REPO_PATH="$TEST_REPO" do_commit "test"

    # Verify commit was made
    run git log --oneline -1
    [[ "$output" =~ "sync:" ]]
}

@test "sync cycle with multiple files" {
    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-commit.sh"

    cd "$TEST_REPO"
    echo "- journal entry" >> journals/2026-01-01.md
    echo "- page content" > pages/test-page.md

    REPO_PATH="$TEST_REPO" do_commit "test"

    # Verify commit includes file count
    run git log --oneline -1
    [[ "$output" =~ "sync:" ]]
    [[ "$output" =~ "2 file" ]]
}

@test "sync cycle with new untracked files" {
    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-commit.sh"

    cd "$TEST_REPO"
    echo "- new page" > pages/new-page.md

    REPO_PATH="$TEST_REPO" do_commit "test"

    # Verify new file was committed
    run git log --oneline -1
    [[ "$output" =~ "sync:" ]]

    # File should be tracked now
    run git ls-files pages/new-page.md
    [ -n "$output" ]
}
