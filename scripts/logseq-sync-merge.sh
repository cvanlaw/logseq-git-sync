#!/usr/bin/env bash
# scripts/logseq-sync-merge.sh
# Handles fetching and merging with Logseq-aware conflict resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logseq-sync-notify.sh
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
        # shellcheck source=/dev/null
        source "$GRAPH_CONFIG"
    else
        echo "Error: Graph config not found: $GRAPH_CONFIG"
        exit 1
    fi

    do_fetch_merge "$GRAPH"
fi
