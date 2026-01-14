#!/usr/bin/env bats
# tests/notify.bats

setup() {
    load 'test_helper/common'
    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-notify.sh"
}

@test "notify function exists" {
    run type notify
    [ "$status" -eq 0 ]
}

@test "log_msg formats correctly" {
    LOG_LEVEL="debug"
    LOG_DIR="$BATS_TMPDIR"
    result=$(log_msg "INFO" "testgraph" "Test message")
    [[ "$result" =~ "[INFO] [testgraph] Test message" ]]
}
