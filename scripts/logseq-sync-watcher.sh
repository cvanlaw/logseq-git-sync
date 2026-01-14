#!/usr/bin/env bash
# scripts/logseq-sync-watcher.sh
# Watches for file changes and triggers commits after quiet period

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logseq-sync-notify.sh
source "${SCRIPT_DIR}/logseq-sync-notify.sh"

GRAPH="${1:-}"
QUIET_PERIOD="${QUIET_PERIOD:-30}"

if [[ -z "$GRAPH" ]]; then
    echo "Usage: logseq-sync-watcher.sh <graph>"
    exit 1
fi

# Load graph config
GRAPH_CONFIG="${HOME}/.config/logseq-git-sync/graphs/${GRAPH}.conf"
if [[ -f "$GRAPH_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$GRAPH_CONFIG"
else
    echo "Error: Graph config not found: $GRAPH_CONFIG"
    exit 1
fi

if [[ -z "${REPO_PATH:-}" ]]; then
    echo "Error: REPO_PATH not set in $GRAPH_CONFIG"
    exit 1
fi

TRIGGER_FILE="/tmp/logseq-sync-trigger-${GRAPH}"
# Use a file to track last change time (avoids subshell variable scoping issues)
TIMESTAMP_FILE="/tmp/logseq-sync-lastchange-${GRAPH}"

log_msg "INFO" "$GRAPH" "Starting watcher for $REPO_PATH (quiet period: ${QUIET_PERIOD}s)"

# Initialize timestamp file
echo "0" > "$TIMESTAMP_FILE"

# Function to check if quiet period elapsed
check_quiet_period() {
    local last_change now elapsed
    last_change=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    elapsed=$((now - last_change))

    if [[ $last_change -gt 0 ]] && [[ $elapsed -ge $QUIET_PERIOD ]]; then
        log_msg "DEBUG" "$GRAPH" "Quiet period elapsed, triggering sync"
        touch "$TRIGGER_FILE"
        echo "0" > "$TIMESTAMP_FILE"
    fi
}

# Watch directories
WATCH_DIRS=("$REPO_PATH/journals" "$REPO_PATH/pages")

# Build exclude patterns
EXCLUDES=(
    --exclude '.git'
    --exclude '.DS_Store'
    --exclude '*.bak'
    --exclude 'logseq'
)

# Verify watch directories exist
for dir in "${WATCH_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_msg "WARN" "$GRAPH" "Watch directory does not exist: $dir"
    fi
done

# Start fswatch in background
# Write timestamp to file on each change (file-based IPC avoids subshell issues)
fswatch -r "${EXCLUDES[@]}" "${WATCH_DIRS[@]}" 2>&1 | while read -r line; do
    # Log fswatch errors (they start with "fswatch" or contain "error")
    if [[ "$line" == fswatch* ]] || [[ "$line" == *error* ]] || [[ "$line" == *Error* ]]; then
        log_msg "ERROR" "$GRAPH" "fswatch: $line"
    else
        date +%s > "$TIMESTAMP_FILE"
        log_msg "DEBUG" "$GRAPH" "Change detected: $line"
    fi
done &

FSWATCH_PID=$!

# Cleanup on exit
cleanup() {
    log_msg "INFO" "$GRAPH" "Stopping watcher"
    kill "$FSWATCH_PID" 2>/dev/null || true
    rm -f "$TIMESTAMP_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT

# Main loop - check quiet period every second
while true; do
    # Verify fswatch pipeline is still running
    if ! kill -0 "$FSWATCH_PID" 2>/dev/null; then
        log_msg "ERROR" "$GRAPH" "fswatch process died, exiting for restart"
        exit 1
    fi
    check_quiet_period
    sleep 1
done
