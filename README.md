# logseq-git-sync

Automated git sync for Logseq notes with multi-graph support and Logseq-aware merging.

## Features

- File watching with quiet period (waits for idle before committing)
- Logseq-aware merging (handles outline blocks intelligently)
- Multi-graph support (sync multiple Logseq graphs)
- macOS launchd integration (runs as background service)
- Conflict preservation (saves conflicted versions for review)

## Installation

```bash
brew install fswatch
make install
logseq-sync add-graph /path/to/logseq/graph
```

## Usage

```bash
logseq-sync status           # Show sync status for all graphs
logseq-sync sync [graph]     # Manual sync (all graphs or specific one)
logseq-sync logs [graph]     # View logs
logseq-sync conflicts        # List unresolved conflicts
logseq-sync start [graph]    # Start background services
logseq-sync stop [graph]     # Stop background services
```

## Configuration

Config files are stored in `~/.config/logseq-git-sync/`:
- `config` - Global settings (QUIET_PERIOD, FETCH_INTERVAL)
- `graphs/*.conf` - Per-graph settings

## Requirements

- macOS (uses launchd for background services)
- fswatch (`brew install fswatch`)
- git
