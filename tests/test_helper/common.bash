# Common test helper functions

# Set up test environment
export TEST_MODE=true
export LOG_DIR="${BATS_TMPDIR}/logs"
mkdir -p "$LOG_DIR"
