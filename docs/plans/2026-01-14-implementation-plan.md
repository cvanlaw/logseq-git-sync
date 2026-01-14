# logseq-git-sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS tool that automatically syncs Logseq notes via git with Logseq-aware merging.

**Architecture:** Shell scripts orchestrated by launchd. fswatch monitors file changes, triggers commit after quiet period. Scheduled jobs handle fetch/merge. Config files define graphs and settings.

**Tech Stack:** Bash, fswatch (Homebrew), launchd, osascript (notifications), bats-core (testing)

---

## Task 1: Project Scaffolding

**Files:**
- Create: `Makefile`
- Create: `.gitignore`
- Create: `README.md`

**Step 1: Create .gitignore**

```gitignore
.DS_Store
*.log
/test-tmp/
```

**Step 2: Create minimal README**

```markdown
# logseq-git-sync

Automated git sync for Logseq notes with multi-graph support and Logseq-aware merging.

## Installation

```bash
brew install fswatch
make install
logseq-sync add-graph /path/to/logseq/graph
```

## Usage

```bash
logseq-sync status      # Show sync status
logseq-sync sync        # Manual sync now
logseq-sync logs        # View logs
```
```

**Step 3: Create Makefile skeleton**

```makefile
.PHONY: help install uninstall status logs lint test clean

PREFIX ?= /usr/local
CONFIG_DIR := $(HOME)/.config/logseq-git-sync
LAUNCH_AGENTS := $(HOME)/Library/LaunchAgents

help:
	@echo "logseq-git-sync"
	@echo ""
	@echo "Targets:"
	@echo "  install     Install scripts and create config directory"
	@echo "  uninstall   Remove scripts and stop services"
	@echo "  add-graph   Add a new Logseq graph (interactive)"
	@echo "  status      Show service status"
	@echo "  logs        Tail logs"
	@echo "  lint        Run shellcheck on all scripts"
	@echo "  test        Run tests"
	@echo "  clean       Remove test artifacts"

install: check-deps
	@echo "Installing logseq-git-sync..."
	@mkdir -p $(CONFIG_DIR)/graphs
	@mkdir -p $(CONFIG_DIR)/logs
	@mkdir -p $(CONFIG_DIR)/conflicts
	@mkdir -p $(PREFIX)/bin
	@cp scripts/logseq-sync $(PREFIX)/bin/
	@cp scripts/logseq-sync-*.sh $(PREFIX)/bin/
	@chmod +x $(PREFIX)/bin/logseq-sync*
	@if [ ! -f $(CONFIG_DIR)/config ]; then \
		cp templates/config.template $(CONFIG_DIR)/config; \
	fi
	@echo "Installed. Run 'logseq-sync add-graph <path>' to add a graph."

uninstall:
	@echo "Uninstalling logseq-git-sync..."
	@logseq-sync stop-all 2>/dev/null || true
	@rm -f $(PREFIX)/bin/logseq-sync*
	@rm -f $(LAUNCH_AGENTS)/com.logseq-sync.*.plist
	@echo "Uninstalled. Config preserved at $(CONFIG_DIR)"

check-deps:
	@command -v fswatch >/dev/null || (echo "Error: fswatch not found. Run: brew install fswatch" && exit 1)
	@command -v git >/dev/null || (echo "Error: git not found" && exit 1)

add-graph:
	@logseq-sync add-graph

status:
	@logseq-sync status

logs:
	@logseq-sync logs

lint:
	@shellcheck scripts/logseq-sync scripts/logseq-sync-*.sh

test:
	@bats tests/

clean:
	@rm -rf test-tmp/
```

**Step 4: Commit scaffolding**

```bash
git add .gitignore README.md Makefile
git commit -m "chore: Initial project scaffolding"
```

---

## Task 2: Config Templates

**Files:**
- Create: `templates/config.template`
- Create: `templates/graph.conf.template`

**Step 1: Create global config template**

```bash
# templates/config.template
# logseq-git-sync global configuration

# Timing
QUIET_PERIOD=30              # Seconds of no edits before commit
FETCH_INTERVAL=300           # Seconds between fetch checks (5 min)
PUSH_RETRY_DELAY=60          # Retry failed push after this delay
MAX_PUSH_RETRIES=3           # Give up after this many failures

# Notifications
NOTIFY_ON_PUSH=true          # Notify on successful push
NOTIFY_ON_MERGE=true         # Notify on successful merge
NOTIFY_ON_ERROR=true         # Notify on any error
NOTIFY_ON_CONFLICT=true      # Notify when manual resolution needed

# Logging
LOG_DIR="${HOME}/.config/logseq-git-sync/logs"
LOG_LEVEL="info"             # debug, info, warn, error
LOG_RETAIN_DAYS=30           # Delete logs older than this

# Optional features
DETECT_LOGSEQ_APP=false      # Watch for Logseq launch/quit
NETWORK_WATCH=false          # Trigger sync on network change
```

**Step 2: Create per-graph config template**

```bash
# templates/graph.conf.template
# Configuration for graph: GRAPH_NAME

REPO_PATH="REPO_PATH_PLACEHOLDER"
REMOTE="origin"
BRANCH="main"

# Override global settings (optional)
# QUIET_PERIOD=30
# FETCH_INTERVAL=300
```

**Step 3: Commit templates**

```bash
git add templates/
git commit -m "feat: Add config templates"
```

---

## Task 3: Notification Helper

**Files:**
- Create: `scripts/logseq-sync-notify.sh`
- Create: `tests/notify.bats`

**Step 1: Create test file**

```bash
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
```

**Step 2: Create test helper**

```bash
mkdir -p tests/test_helper
cat > tests/test_helper/common.bash << 'EOF'
# Common test helper functions

# Set up test environment
export TEST_MODE=true
export LOG_DIR="${BATS_TMPDIR}/logs"
mkdir -p "$LOG_DIR"
EOF
```

**Step 3: Run test to verify it fails**

```bash
bats tests/notify.bats
```

Expected: FAIL (file doesn't exist yet)

**Step 4: Create notification script**

```bash
#!/usr/bin/env bash
# scripts/logseq-sync-notify.sh
# Notification and logging utilities for logseq-git-sync

set -euo pipefail

# Source config if not already loaded
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    CONFIG_FILE="${HOME}/.config/logseq-git-sync/config"
    if [[ -f "$CONFIG_FILE" ]]; then
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

# Log levels (lower = more severe)
declare -A LOG_LEVELS=([error]=0 [warn]=1 [info]=2 [debug]=3)

log_msg() {
    local level="$1"
    local graph="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local level_lower="${level,,}"
    local config_level="${LOG_LEVEL,,}"

    # Check if we should log this level
    if [[ ${LOG_LEVELS[$level_lower]:-2} -le ${LOG_LEVELS[$config_level]:-2} ]]; then
        local log_line="$timestamp [$level] [$graph] $message"
        echo "$log_line"

        # Also write to log file
        local log_file="$LOG_DIR/$(date '+%Y-%m-%d').log"
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
```

**Step 5: Run test to verify it passes**

```bash
chmod +x scripts/logseq-sync-notify.sh
bats tests/notify.bats
```

Expected: PASS

**Step 6: Commit**

```bash
git add scripts/logseq-sync-notify.sh tests/
git commit -m "feat: Add notification and logging utilities"
```

---

## Task 4: Commit Script

**Files:**
- Create: `scripts/logseq-sync-commit.sh`
- Create: `tests/commit.bats`

**Step 1: Create test file**

```bash
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
```

**Step 2: Run test to verify it fails**

```bash
bats tests/commit.bats
```

Expected: FAIL (script doesn't exist)

**Step 3: Create commit script**

```bash
#!/usr/bin/env bash
# scripts/logseq-sync-commit.sh
# Handles committing changes for a Logseq graph

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logseq-sync-notify.sh"

do_commit() {
    local graph="$1"
    local repo_path="${REPO_PATH:-}"

    if [[ -z "$repo_path" ]]; then
        notify_error "$graph" "REPO_PATH not set"
        return 1
    fi

    cd "$repo_path"

    # Check for changes
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        log_msg "DEBUG" "$graph" "No changes to commit"
        return 0
    fi

    # Stage all changes
    git add -A

    # Generate commit message
    local changed_files
    changed_files=$(git diff --cached --name-only | head -5 | tr '\n' ', ' | sed 's/,$//')
    local file_count
    file_count=$(git diff --cached --name-only | wc -l | tr -d ' ')

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local commit_msg="sync: $timestamp"
    if [[ "$file_count" -gt 0 ]]; then
        commit_msg="sync: $file_count file(s) - $changed_files"
    fi

    # Commit
    if git commit -m "$commit_msg" >/dev/null 2>&1; then
        log_msg "INFO" "$graph" "Committed: $commit_msg"
        return 0
    else
        log_msg "DEBUG" "$graph" "Nothing to commit after staging"
        return 0
    fi
}

do_push() {
    local graph="$1"
    local repo_path="${REPO_PATH:-}"
    local remote="${REMOTE:-origin}"
    local branch="${BRANCH:-main}"
    local max_retries="${MAX_PUSH_RETRIES:-3}"
    local retry_delay="${PUSH_RETRY_DELAY:-60}"

    cd "$repo_path"

    # Check if we have commits to push
    if git diff --quiet "$remote/$branch" HEAD 2>/dev/null; then
        log_msg "DEBUG" "$graph" "Nothing to push"
        return 0
    fi

    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if git push "$remote" "$branch" 2>/dev/null; then
            notify_success "$graph" "push" "Pushed to $remote/$branch"
            return 0
        fi

        log_msg "WARN" "$graph" "Push failed, attempt $attempt/$max_retries"

        if [[ $attempt -lt $max_retries ]]; then
            sleep "$retry_delay"
        fi
        ((attempt++))
    done

    notify_error "$graph" "Push failed after $max_retries attempts"
    return 1
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    GRAPH="${1:-}"
    ACTION="${2:-commit}"

    if [[ -z "$GRAPH" ]]; then
        echo "Usage: logseq-sync-commit.sh <graph> [commit|push]"
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

    case "$ACTION" in
        commit)
            do_commit "$GRAPH"
            ;;
        push)
            do_push "$GRAPH"
            ;;
        *)
            echo "Unknown action: $ACTION"
            exit 1
            ;;
    esac
fi
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/logseq-sync-commit.sh
bats tests/commit.bats
```

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/logseq-sync-commit.sh tests/commit.bats
git commit -m "feat: Add commit and push scripts"
```

---

## Task 5: Merge Script

**Files:**
- Create: `scripts/logseq-sync-merge.sh`
- Create: `tests/merge.bats`

**Step 1: Create test file**

```bash
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
```

**Step 2: Run test to verify it fails**

```bash
bats tests/merge.bats
```

Expected: FAIL

**Step 3: Create merge script**

```bash
#!/usr/bin/env bash
# scripts/logseq-sync-merge.sh
# Handles fetching and merging with Logseq-aware conflict resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logseq-sync-notify.sh"

CONFLICT_DIR="${HOME}/.config/logseq-git-sync/conflicts"

do_fetch_merge() {
    local graph="$1"
    local repo_path="${REPO_PATH:-}"
    local remote="${REMOTE:-origin}"
    local branch="${BRANCH:-main}"

    if [[ -z "$repo_path" ]]; then
        notify_error "$graph" "REPO_PATH not set"
        return 1
    fi

    cd "$repo_path"

    # Fetch
    log_msg "DEBUG" "$graph" "Fetching from $remote"
    if ! git fetch "$remote" 2>/dev/null; then
        notify_error "$graph" "Fetch failed"
        return 1
    fi

    # Check if we're behind
    local local_head remote_head base
    local_head=$(git rev-parse HEAD)
    remote_head=$(git rev-parse "$remote/$branch" 2>/dev/null) || {
        log_msg "DEBUG" "$graph" "Remote branch not found, skipping merge"
        return 0
    }
    base=$(git merge-base HEAD "$remote/$branch" 2>/dev/null) || base=""

    if [[ "$local_head" == "$remote_head" ]]; then
        log_msg "DEBUG" "$graph" "Already up to date"
        return 0
    fi

    if [[ "$local_head" == "$base" ]]; then
        # We can fast-forward
        log_msg "INFO" "$graph" "Fast-forwarding to $remote/$branch"
        git merge --ff-only "$remote/$branch"
        notify_success "$graph" "merge" "Fast-forward merge complete"
        return 0
    fi

    # Check for uncommitted changes
    local had_stash=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_msg "INFO" "$graph" "Stashing local changes before merge"
        git stash push -m "logseq-sync auto-stash"
        had_stash=true
    fi

    # Try normal merge
    log_msg "INFO" "$graph" "Attempting merge with $remote/$branch"
    if git merge "$remote/$branch" -m "sync: merge from $remote/$branch" 2>/dev/null; then
        notify_success "$graph" "merge" "Merged from $remote/$branch"

        if [[ "$had_stash" == "true" ]]; then
            git stash pop || {
                notify_conflict "$graph" "Stash pop failed - manual resolution needed"
            }
        fi
        return 0
    fi

    # Merge failed - try Logseq-aware resolution
    log_msg "INFO" "$graph" "Standard merge failed, trying Logseq-aware resolution"

    if try_logseq_merge "$graph"; then
        if [[ "$had_stash" == "true" ]]; then
            git stash pop || {
                notify_conflict "$graph" "Stash pop failed - manual resolution needed"
            }
        fi
        return 0
    fi

    # True conflict - abort and stash
    log_msg "WARN" "$graph" "True conflict detected, aborting merge"
    git merge --abort 2>/dev/null || true

    # Save conflict info
    save_conflict_info "$graph"

    # Stash local commits and reset to remote
    local stash_msg="logseq-sync conflict $(date '+%Y-%m-%d %H:%M:%S')"
    git stash push -m "$stash_msg" --include-untracked 2>/dev/null || true
    git reset --hard "$remote/$branch"

    notify_conflict "$graph" "Conflict detected - local changes stashed. Run 'logseq-sync conflicts' for details."

    return 1
}

try_logseq_merge() {
    local graph="$1"

    # Get list of conflicting files
    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null) || return 1

    if [[ -z "$conflicts" ]]; then
        return 1
    fi

    # Check if all conflicts are in journals/ or pages/
    while IFS= read -r file; do
        if [[ ! "$file" =~ ^(journals|pages)/ ]]; then
            log_msg "DEBUG" "$graph" "Non-Logseq file in conflict: $file"
            return 1
        fi

        # Try to resolve by keeping both versions for block-based content
        if ! resolve_logseq_conflict "$file"; then
            return 1
        fi
    done <<< "$conflicts"

    # All conflicts resolved, complete the merge
    git add -A
    if git commit -m "sync: merge with Logseq-aware resolution" 2>/dev/null; then
        notify_success "$graph" "merge" "Merged with Logseq-aware conflict resolution"
        return 0
    fi

    return 1
}

resolve_logseq_conflict() {
    local file="$1"

    # For now, use a simple strategy: take theirs for true conflicts
    # A more sophisticated approach would parse block IDs

    # Check if it's just both sides adding content (common case)
    if grep -q "^<<<<<<< HEAD" "$file" 2>/dev/null; then
        # Simple resolution: concatenate both versions
        # Remove conflict markers, keep all content
        local temp_file
        temp_file=$(mktemp)

        # This sed removes conflict markers and keeps all content
        sed -e '/^<<<<<<< /d' -e '/^=======/d' -e '/^>>>>>>> /d' "$file" > "$temp_file"
        mv "$temp_file" "$file"

        return 0
    fi

    return 1
}

save_conflict_info() {
    local graph="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d-%H%M%S')

    mkdir -p "$CONFLICT_DIR"
    local conflict_file="$CONFLICT_DIR/${graph}-${timestamp}.log"

    {
        echo "Conflict detected at $(date)"
        echo "Graph: $graph"
        echo "Repository: $REPO_PATH"
        echo ""
        echo "Conflicting files:"
        git diff --name-only --diff-filter=U 2>/dev/null || echo "(unable to determine)"
        echo ""
        echo "Local HEAD: $(git rev-parse HEAD)"
        echo "Remote HEAD: $(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null || echo 'unknown')"
        echo ""
        echo "Stash reference: $(git stash list | head -1)"
    } > "$conflict_file"

    log_msg "INFO" "$graph" "Conflict details saved to $conflict_file"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    GRAPH="${1:-}"

    if [[ -z "$GRAPH" ]]; then
        echo "Usage: logseq-sync-merge.sh <graph>"
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

    do_fetch_merge "$GRAPH"
fi
```

**Step 4: Run test to verify it passes**

```bash
chmod +x scripts/logseq-sync-merge.sh
bats tests/merge.bats
```

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/logseq-sync-merge.sh tests/merge.bats
git commit -m "feat: Add fetch-merge with Logseq-aware conflict resolution"
```

---

## Task 6: File Watcher Script

**Files:**
- Create: `scripts/logseq-sync-watcher.sh`

**Step 1: Create watcher script**

```bash
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
```

**Step 2: Commit**

```bash
chmod +x scripts/logseq-sync-watcher.sh
git add scripts/logseq-sync-watcher.sh
git commit -m "feat: Add file watcher with debounce"
```

---

## Task 7: Main CLI Script

**Files:**
- Create: `scripts/logseq-sync`

**Step 1: Create main CLI**

```bash
#!/usr/bin/env bash
# scripts/logseq-sync
# Main CLI entry point for logseq-git-sync

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/logseq-git-sync"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"

# Source helpers
source "${SCRIPT_DIR}/logseq-sync-notify.sh" 2>/dev/null || true

usage() {
    cat << EOF
logseq-git-sync v$VERSION

Usage: logseq-sync <command> [options]

Commands:
  add-graph <path>   Add a new Logseq graph
  remove-graph <n>   Remove a graph
  status             Show status of all graphs
  sync [graph]       Manually sync a graph (or all)
  logs [graph]       Tail logs
  conflicts          List unresolved conflicts
  start [graph]      Start services for a graph (or all)
  stop [graph]       Stop services for a graph (or all)
  stop-all           Stop all services
  install-services   Regenerate and load launchd plists

EOF
}

list_graphs() {
    find "$CONFIG_DIR/graphs" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

add_graph() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        echo "Usage: logseq-sync add-graph <path>"
        echo ""
        echo "Path should be the root of your Logseq graph (contains journals/ and pages/)"
        exit 1
    fi

    # Expand path
    path=$(cd "$path" 2>/dev/null && pwd) || {
        echo "Error: Path does not exist: $path"
        exit 1
    }

    # Verify it's a git repo with Logseq structure
    if [[ ! -d "$path/.git" ]]; then
        echo "Error: Not a git repository: $path"
        exit 1
    fi

    if [[ ! -d "$path/journals" ]] && [[ ! -d "$path/pages" ]]; then
        echo "Warning: No journals/ or pages/ directory found. Is this a Logseq graph?"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # Get graph name
    local default_name
    default_name=$(basename "$path")
    read -p "Graph name [$default_name]: " graph_name
    graph_name="${graph_name:-$default_name}"

    # Sanitize name
    graph_name=$(echo "$graph_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')

    # Check if exists
    local config_file="$CONFIG_DIR/graphs/${graph_name}.conf"
    if [[ -f "$config_file" ]]; then
        echo "Error: Graph '$graph_name' already exists"
        exit 1
    fi

    # Create config
    mkdir -p "$CONFIG_DIR/graphs"
    cat > "$config_file" << EOF
# Configuration for graph: $graph_name

REPO_PATH="$path"
REMOTE="origin"
BRANCH="main"

# Override global settings (optional)
# QUIET_PERIOD=30
# FETCH_INTERVAL=300
EOF

    echo "Created config: $config_file"

    # Generate launchd plists
    generate_plists "$graph_name"

    # Start services
    start_graph "$graph_name"

    echo ""
    echo "Graph '$graph_name' added and started!"
    echo "Run 'logseq-sync status' to verify."
}

generate_plists() {
    local graph="$1"
    local config_file="$CONFIG_DIR/graphs/${graph}.conf"

    source "$config_file"

    mkdir -p "$LAUNCH_AGENTS"

    # Watcher plist
    cat > "$LAUNCH_AGENTS/com.logseq-sync.watcher.${graph}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.logseq-sync.watcher.${graph}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/logseq-sync-watcher.sh</string>
        <string>${graph}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/logs/watcher-${graph}.err</string>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/logs/watcher-${graph}.out</string>
</dict>
</plist>
EOF

    # Commit trigger plist (watches trigger file)
    cat > "$LAUNCH_AGENTS/com.logseq-sync.commit.${graph}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.logseq-sync.commit.${graph}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/logseq-sync-commit.sh</string>
        <string>${graph}</string>
        <string>commit</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/tmp/logseq-sync-trigger-${graph}</string>
    </array>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/logs/commit-${graph}.err</string>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/logs/commit-${graph}.out</string>
</dict>
</plist>
EOF

    # Scheduled fetch plist
    source "$CONFIG_DIR/config" 2>/dev/null || true
    local fetch_interval="${FETCH_INTERVAL:-300}"

    cat > "$LAUNCH_AGENTS/com.logseq-sync.fetch.${graph}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.logseq-sync.fetch.${graph}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/logseq-sync-merge.sh</string>
        <string>${graph}</string>
    </array>
    <key>StartInterval</key>
    <integer>${fetch_interval}</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/logs/fetch-${graph}.err</string>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/logs/fetch-${graph}.out</string>
</dict>
</plist>
EOF

    echo "Generated launchd plists for $graph"
}

start_graph() {
    local graph="$1"

    for plist in "$LAUNCH_AGENTS"/com.logseq-sync.*.${graph}.plist; do
        [[ -f "$plist" ]] || continue
        launchctl load "$plist" 2>/dev/null || true
    done

    echo "Started services for $graph"
}

stop_graph() {
    local graph="$1"

    for plist in "$LAUNCH_AGENTS"/com.logseq-sync.*.${graph}.plist; do
        [[ -f "$plist" ]] || continue
        launchctl unload "$plist" 2>/dev/null || true
    done

    echo "Stopped services for $graph"
}

stop_all() {
    for graph in $(list_graphs); do
        stop_graph "$graph"
    done
}

status() {
    echo "logseq-git-sync status"
    echo "======================"
    echo ""

    local graphs
    graphs=$(list_graphs)

    if [[ -z "$graphs" ]]; then
        echo "No graphs configured."
        echo "Run 'logseq-sync add-graph <path>' to add one."
        exit 0
    fi

    for graph in $graphs; do
        local config_file="$CONFIG_DIR/graphs/${graph}.conf"
        source "$config_file"

        echo "Graph: $graph"
        echo "  Path: $REPO_PATH"

        # Check services
        local watcher_status="stopped"
        local fetch_status="stopped"

        if launchctl list | grep -q "com.logseq-sync.watcher.${graph}"; then
            watcher_status="running"
        fi
        if launchctl list | grep -q "com.logseq-sync.fetch.${graph}"; then
            fetch_status="running"
        fi

        echo "  Watcher: $watcher_status"
        echo "  Fetch: $fetch_status"

        # Git status
        if [[ -d "$REPO_PATH" ]]; then
            cd "$REPO_PATH"
            local branch
            branch=$(git branch --show-current 2>/dev/null || echo "unknown")
            local status="clean"
            if ! git diff --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
                status="has changes"
            fi
            echo "  Branch: $branch ($status)"
        fi

        echo ""
    done
}

sync_graph() {
    local graph="$1"
    local config_file="$CONFIG_DIR/graphs/${graph}.conf"

    if [[ ! -f "$config_file" ]]; then
        echo "Error: Graph not found: $graph"
        exit 1
    fi

    source "$config_file"

    echo "Syncing $graph..."

    # Fetch and merge first
    "${SCRIPT_DIR}/logseq-sync-merge.sh" "$graph" || true

    # Then commit and push
    "${SCRIPT_DIR}/logseq-sync-commit.sh" "$graph" commit
    "${SCRIPT_DIR}/logseq-sync-commit.sh" "$graph" push || true

    echo "Done."
}

show_logs() {
    local graph="${1:-}"

    if [[ -n "$graph" ]]; then
        tail -f "$CONFIG_DIR/logs/"*"${graph}"* 2>/dev/null || {
            echo "No logs found for $graph"
        }
    else
        tail -f "$CONFIG_DIR/logs/"*.log 2>/dev/null || {
            echo "No logs found"
        }
    fi
}

show_conflicts() {
    local conflict_dir="$CONFIG_DIR/conflicts"

    if [[ ! -d "$conflict_dir" ]] || [[ -z "$(ls -A "$conflict_dir" 2>/dev/null)" ]]; then
        echo "No conflicts recorded."
        exit 0
    fi

    echo "Unresolved conflicts:"
    echo ""

    for conflict_file in "$conflict_dir"/*.log; do
        [[ -f "$conflict_file" ]] || continue
        echo "--- $(basename "$conflict_file") ---"
        cat "$conflict_file"
        echo ""
    done
}

# Main command dispatch
case "${1:-}" in
    add-graph)
        add_graph "${2:-}"
        ;;
    remove-graph)
        # TODO: implement
        echo "Not implemented yet"
        ;;
    status)
        status
        ;;
    sync)
        if [[ -n "${2:-}" ]]; then
            sync_graph "$2"
        else
            for graph in $(list_graphs); do
                sync_graph "$graph"
            done
        fi
        ;;
    logs)
        show_logs "${2:-}"
        ;;
    conflicts)
        show_conflicts
        ;;
    start)
        if [[ -n "${2:-}" ]]; then
            start_graph "$2"
        else
            for graph in $(list_graphs); do
                start_graph "$graph"
            done
        fi
        ;;
    stop)
        if [[ -n "${2:-}" ]]; then
            stop_graph "$2"
        else
            stop_all
        fi
        ;;
    stop-all)
        stop_all
        ;;
    install-services)
        for graph in $(list_graphs); do
            generate_plists "$graph"
            start_graph "$graph"
        done
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
```

**Step 2: Commit**

```bash
chmod +x scripts/logseq-sync
git add scripts/logseq-sync
git commit -m "feat: Add main CLI with add-graph, status, sync commands"
```

---

## Task 8: Integration Testing

**Files:**
- Create: `tests/integration.bats`

**Step 1: Create integration test**

```bash
#!/usr/bin/env bats
# tests/integration.bats

setup() {
    export TEST_MODE=true
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

    # Source scripts
    source "$BATS_TEST_DIRNAME/../scripts/logseq-sync-notify.sh"
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
```

**Step 2: Run tests**

```bash
bats tests/integration.bats
```

**Step 3: Commit**

```bash
git add tests/integration.bats
git commit -m "test: Add integration tests"
```

---

## Task 9: Final Polish

**Files:**
- Update: `Makefile` (add test dependency check)
- Update: `README.md` (expand documentation)

**Step 1: Update Makefile with bats check**

Add to `check-deps` target:
```makefile
check-deps:
	@command -v fswatch >/dev/null || (echo "Error: fswatch not found. Run: brew install fswatch" && exit 1)
	@command -v git >/dev/null || (echo "Error: git not found" && exit 1)

check-test-deps:
	@command -v bats >/dev/null || (echo "Warning: bats not found. Run: brew install bats-core" && exit 0)

test: check-test-deps
	@if command -v bats >/dev/null; then bats tests/; else echo "Skipping tests (bats not installed)"; fi
```

**Step 2: Commit final changes**

```bash
git add Makefile README.md
git commit -m "chore: Final polish - test deps, readme"
```

---

## Summary

After completing all tasks:

```bash
# Install
cd ~/repos/cvanlaw/logseq-git-sync
make install

# Add your graph
logseq-sync add-graph ~/repos/cvanlaw/logseq-notes

# Verify
logseq-sync status
```

The system will then:
- Watch for file changes in journals/ and pages/
- Commit after 30 seconds of quiet
- Fetch/merge every 5 minutes
- Notify on successful pushes, merges, and conflicts
