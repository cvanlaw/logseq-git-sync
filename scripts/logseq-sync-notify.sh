#!/usr/bin/env bash
# scripts/logseq-sync-notify.sh
# Notification and logging utilities for logseq-git-sync

set -euo pipefail

# Source config if not already loaded
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    CONFIG_FILE="${HOME}/.config/logseq-git-sync/config"
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
fi

# Defaults
LOG_DIR="${LOG_DIR:-${HOME}/.config/logseq-git-sync/logs}"
LOG_LEVEL="${LOG_LEVEL:-info}"
NOTIFY_ON_ERROR="${NOTIFY_ON_ERROR:-true}"
NOTIFY_ON_PUSH="${NOTIFY_ON_PUSH:-true}"
NOTIFY_ON_MERGE="${NOTIFY_ON_MERGE:-true}"
NOTIFY_ON_CONFLICT="${NOTIFY_ON_CONFLICT:-true}"

# Get numeric log level (lower = more severe)
# error=0, warn=1, info=2, debug=3
get_log_level_num() {
    local level
    level=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$level" in
        error) echo 0 ;;
        warn)  echo 1 ;;
        info)  echo 2 ;;
        debug) echo 3 ;;
        *)     echo 2 ;;
    esac
}

log_msg() {
    local level="$1"
    local graph="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local level_num
    local config_level_num
    level_num=$(get_log_level_num "$level")
    config_level_num=$(get_log_level_num "$LOG_LEVEL")

    # Check if we should log this level
    if [[ $level_num -le $config_level_num ]]; then
        local log_line="$timestamp [$level] [$graph] $message"
        echo "$log_line"

        # Also write to log file
        local log_file
        log_file="$LOG_DIR/$(date '+%Y-%m-%d').log"
        mkdir -p "$LOG_DIR"
        echo "$log_line" >> "$log_file"
    fi
}

notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"

    # Skip if in test mode
    [[ "${TEST_MODE:-}" == "true" ]] && return 0

    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

notify_error() {
    local graph="$1"
    local message="$2"

    log_msg "ERROR" "$graph" "$message"

    if [[ "$NOTIFY_ON_ERROR" == "true" ]]; then
        notify "Logseq Sync Error" "[$graph] $message" "Basso"
    fi
}

notify_success() {
    local graph="$1"
    local action="$2"
    local message="$3"

    log_msg "INFO" "$graph" "$message"

    case "$action" in
        push)
            [[ "$NOTIFY_ON_PUSH" == "true" ]] && notify "Logseq Sync" "[$graph] $message"
            ;;
        merge)
            [[ "$NOTIFY_ON_MERGE" == "true" ]] && notify "Logseq Sync" "[$graph] $message"
            ;;
    esac
}

notify_conflict() {
    local graph="$1"
    local message="$2"

    log_msg "WARN" "$graph" "$message"

    if [[ "$NOTIFY_ON_CONFLICT" == "true" ]]; then
        notify "Logseq Sync - Action Required" "[$graph] $message" "Basso"
    fi
}

# Clean old logs
clean_old_logs() {
    local retain_days="${LOG_RETAIN_DAYS:-30}"
    find "$LOG_DIR" -name "*.log" -mtime "+$retain_days" -delete 2>/dev/null || true
}
