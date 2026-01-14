#!/usr/bin/env bash
# scripts/logseq-sync-commit.sh
# Handles committing changes for a Logseq graph

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logseq-sync-notify.sh
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
        # shellcheck source=/dev/null
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
