#!/usr/bin/env bats
# tests/merge.bats

setup() {
    load 'test_helper/common'

    # Create test repos (local and "remote")
    export REMOTE_REPO="$BATS_TMPDIR/remote-repo-$$"
    export LOCAL_REPO="$BATS_TMPDIR/local-repo-$$"

    # Set up remote
    mkdir -p "$REMOTE_REPO"
    cd "$REMOTE_REPO"
    git init --bare

    # Set up local
    git clone "$REMOTE_REPO" "$LOCAL_REPO"
    cd "$LOCAL_REPO"
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p journals pages
    echo "- initial" > journals/2026-01-01.md
    git add .
    git commit -m "initial"
    git push origin main
}

teardown() {
    rm -rf "$REMOTE_REPO" "$LOCAL_REPO"
}

@test "fast-forward merge works" {
    cd "$LOCAL_REPO"

    # Simulate remote change
    git checkout -b temp
    echo "- remote entry" >> journals/2026-01-01.md
    git add .
    git commit -m "remote change"
    git push origin temp:main
    git checkout main
    git reset --hard HEAD~1 2>/dev/null || git reset --hard origin/main~1

    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-merge.sh"

    REPO_PATH="$LOCAL_REPO" REMOTE="origin" BRANCH="main" do_fetch_merge "test"

    # Should have the remote change
    run cat journals/2026-01-01.md
    [[ "$output" =~ "remote entry" ]]
}
