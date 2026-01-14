# logseq-git-sync

Automated git sync for Logseq notes with intelligent conflict resolution.

## The Problem

Syncing Logseq graphs via git across multiple devices leads to frequent merge conflicts. Traditional git merges force manual resolution of block-level conflicts, even when changes are on completely different pages or days.

## The Solution

logseq-git-sync watches your graph, commits changes after a quiet period, and handles merges intelligently. When conflicts occur in Logseq files, it preserves content from both sides (since Logseq's outline format is append-friendly) rather than forcing manual resolution.

## Features

- **Quiet period commits** - Waits for idle time before committing (default 30s)
- **Logseq-aware merging** - Resolves conflicts by keeping content from both sides
- **Multi-graph support** - Sync multiple Logseq graphs independently
- **Background service** - Runs via macOS launchd
- **Conflict preservation** - Saves conflicted versions for manual review when needed
- **Configurable notifications** - macOS notifications for sync events

## Requirements

- macOS (uses launchd for background services)
- git
- fswatch

## Installation

```bash
# Install fswatch
brew install fswatch

# Install logseq-git-sync
make install

# Add your first graph (must be an existing git repo)
logseq-sync add-graph /path/to/your/logseq/graph
```

The `add-graph` command will:
1. Validate the directory is a git repo with Logseq structure
2. Create a configuration file for the graph
3. Generate and load launchd services

## Usage

```bash
logseq-sync status             # Show status of all graphs
logseq-sync sync [graph]       # Manual sync (all or specific graph)
logseq-sync start [graph]      # Start background services
logseq-sync stop [graph]       # Stop background services
logseq-sync stop-all           # Stop all services
logseq-sync logs [graph]       # View logs
logseq-sync conflicts          # List unresolved conflicts
logseq-sync install-services   # Regenerate launchd plists
```

## How It Works

```
Edit in Logseq → Watcher detects changes → Wait for quiet period (30s)
    → Commit changes → Push to remote → Fetch & merge (every 5 min)
```

Three launchd services run per graph:
- **Watcher** - Monitors `journals/` and `pages/` via fswatch
- **Commit** - Triggers on changes, commits and pushes
- **Fetch** - Periodic fetch and merge (default: every 5 minutes)

### Merge Strategy

1. Try standard git merge (fast-forward when possible)
2. On conflict in `journals/` or `pages/` files: remove conflict markers, keep all content
3. If merge still fails: stash local changes, reset to remote, save conflict info

## Configuration

Config files are stored in `~/.config/logseq-git-sync/`.

### Global Settings (`config`)

```bash
# Timing
QUIET_PERIOD=30              # Seconds of no edits before commit
FETCH_INTERVAL=300           # Seconds between fetch checks (5 min)
PUSH_RETRY_DELAY=60          # Retry delay for failed push
MAX_PUSH_RETRIES=3           # Max push retry attempts

# Notifications
NOTIFY_ON_PUSH=true          # Notify on successful push
NOTIFY_ON_MERGE=true         # Notify on successful merge
NOTIFY_ON_ERROR=true         # Notify on errors
NOTIFY_ON_CONFLICT=true      # Notify when manual resolution needed

# Logging
LOG_LEVEL="info"             # debug, info, warn, error
LOG_RETAIN_DAYS=30           # Auto-delete old logs
```

### Per-Graph Settings (`graphs/<name>.conf`)

```bash
REPO_PATH="/path/to/graph"
REMOTE="origin"
BRANCH="main"

# Override any global setting per-graph
# QUIET_PERIOD=60
```

## Troubleshooting

**Services not starting**
```bash
# Check if fswatch is installed
which fswatch

# Verify launchd plists exist
ls ~/Library/LaunchAgents/com.logseq-sync.*

# Regenerate services
logseq-sync install-services
```

**Sync not triggering**
```bash
# Check watcher logs
logseq-sync logs <graph-name>

# Verify graph config
cat ~/.config/logseq-git-sync/graphs/<name>.conf
```

**Conflicts not auto-resolving**
- Check `~/.config/logseq-git-sync/conflicts/` for saved conflict info
- Conflicts outside `journals/` and `pages/` require manual resolution
- Run `logseq-sync conflicts` to list pending conflicts

## Uninstall

```bash
make uninstall
```

This removes:
- Scripts from `/usr/local/bin`
- launchd plists from `~/Library/LaunchAgents`
- Does NOT remove config/logs in `~/.config/logseq-git-sync/`

## Development

```bash
make test    # Run tests (requires bats-core)
make lint    # Run shellcheck
```
