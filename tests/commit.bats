#!/usr/bin/env bats
# tests/commit.bats

setup() {
    load 'test_helper/common'

    # Create a test git repo
    export TEST_REPO="$BATS_TMPDIR/test-repo-$$"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial"
}

teardown() {
    rm -rf "$TEST_REPO"
}

@test "commit with changes creates commit" {
    cd "$TEST_REPO"
    echo "modified" >> file.txt

    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-commit.sh"

    REPO_PATH="$TEST_REPO" do_commit "test"

    # Check commit was made
    run git log --oneline -1
    [[ "$output" =~ "sync:" ]]
}

@test "commit with no changes does nothing" {
    cd "$TEST_REPO"

    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-commit.sh"

    local before=$(git rev-parse HEAD)
    REPO_PATH="$TEST_REPO" do_commit "test"
    local after=$(git rev-parse HEAD)

    [ "$before" == "$after" ]
}
