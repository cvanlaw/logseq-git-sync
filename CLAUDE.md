# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

logseq-git-sync is a macOS background service for automatic git synchronization of Logseq notes. It provides intelligent, Logseq-aware merge conflict resolution that preserves content from both sides rather than forcing manual resolution.

## Common Commands

```bash
# Build/Install
make install          # Install scripts to /usr/local/bin, create config dirs
make uninstall        # Remove installed scripts and launchd agents

# Testing
make test             # Run all bats tests
bats tests/commit.bats  # Run a single test file

# Linting
make lint             # Run shellcheck on all scripts

# Operations (after install)
logseq-sync add-graph <path>   # Register a new graph
logseq-sync status             # Show status of all graphs
logseq-sync sync [graph]       # Manual sync
logseq-sync start [graph]      # Start background services
logseq-sync stop [graph]       # Stop services
logseq-sync logs [graph]       # View logs
logseq-sync conflicts          # List unresolved conflicts
```

## Architecture

### Script Pipeline

```
User edits → Watcher (fswatch) → Quiet period (30s) → Commit → Push → Fetch/Merge
```

1. **logseq-sync** (`scripts/logseq-sync`) - Main CLI entry point. Handles graph registration, launchd plist generation, and user commands.

2. **logseq-sync-watcher.sh** - Monitors `journals/` and `pages/` with fswatch. Uses file-based IPC (touch `/tmp/logseq-sync-trigger-{graph}`) to signal the commit service after a quiet period.

3. **logseq-sync-commit.sh** - Stages changes, creates commits, pushes with retry logic.

4. **logseq-sync-merge.sh** - Fetches and merges with Logseq-aware conflict resolution:
   - Tries standard merge first
   - On conflict: removes markers, concatenates both sides (Logseq content is additive)
   - On true conflict: stashes local changes, resets to remote, saves conflict info

5. **logseq-sync-notify.sh** - Centralized logging and macOS notifications via osascript.

### Background Services (launchd)

Each registered graph gets 3 launchd plists in `~/Library/LaunchAgents/`:
- `com.logseq-sync.watcher.{graph}.plist` - Continuous file watcher
- `com.logseq-sync.commit.{graph}.plist` - Triggers on `/tmp/logseq-sync-trigger-{graph}` touch
- `com.logseq-sync.fetch.{graph}.plist` - Scheduled fetch every 5 minutes

### Configuration

- Global: `~/.config/logseq-git-sync/config`
- Per-graph: `~/.config/logseq-git-sync/graphs/{name}.conf`
- Logs: `~/.config/logseq-git-sync/logs/`
- Conflicts: `~/.config/logseq-git-sync/conflicts/`

## Testing

Tests use bats-core and create temporary git repos for isolation. Set `TEST_MODE=1` to disable actual notifications during tests.

Test files:
- `tests/commit.bats` - Commit/push operations
- `tests/merge.bats` - Fetch/merge with conflict handling
- `tests/notify.bats` - Logging utilities
- `tests/integration.bats` - Full sync cycle

## Key Implementation Details

- **File-based IPC**: The watcher uses temp files instead of variables to communicate across subshells (bash scoping workaround)
- **Quiet period debouncing**: Default 30 seconds of no changes before triggering a commit
- **Graph validation**: Checks for `.git`, `journals/`, and `pages/` directories
- **Logseq-aware merging**: Conflict markers are removed and content concatenated because Logseq data is append-friendly
