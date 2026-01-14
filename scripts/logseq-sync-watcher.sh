#!/usr/bin/env bash
# scripts/logseq-sync-watcher.sh
# Watches for file changes and triggers commits after quiet period

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
LAST_CHANGE=0

log_msg "INFO" "$GRAPH" "Starting watcher for $REPO_PATH (quiet period: ${QUIET_PERIOD}s)"

# Function to handle file changes
handle_change() {
    LAST_CHANGE=$(date +%s)
    log_msg "DEBUG" "$GRAPH" "Change detected, resetting quiet period timer"
}

# Function to check if quiet period elapsed
check_quiet_period() {
    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_CHANGE))

    if [[ $LAST_CHANGE -gt 0 ]] && [[ $elapsed -ge $QUIET_PERIOD ]]; then
        log_msg "DEBUG" "$GRAPH" "Quiet period elapsed, triggering sync"
        touch "$TRIGGER_FILE"
        LAST_CHANGE=0
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

# Start fswatch in background, piping to handler
fswatch -r "${EXCLUDES[@]}" "${WATCH_DIRS[@]}" 2>/dev/null | while read -r _; do
    handle_change
done &

FSWATCH_PID=$!

# Cleanup on exit
cleanup() {
    log_msg "INFO" "$GRAPH" "Stopping watcher"
    kill "$FSWATCH_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Main loop - check quiet period every second
while true; do
    check_quiet_period
    sleep 1
done
