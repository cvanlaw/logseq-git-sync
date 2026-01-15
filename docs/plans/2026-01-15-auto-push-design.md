# Auto-Push After Commit Design

## Problem

Currently, the commit service only commits changes locally. Push never happens automatically - users must run `logseq-sync sync` manually. This means changes accumulate locally and aren't synced to remote until manual intervention.

## Use Case

Single-user, multiple devices. The user wants changes pushed immediately so other devices always have the latest.

## Solution

Chain `do_push` after successful `do_commit` in the commit script. No new services, plists, or config options needed.

## Implementation

In `scripts/logseq-sync-commit.sh`, modify the commit action:

```bash
case "$ACTION" in
    commit)
        if do_commit "$GRAPH"; then
            do_push "$GRAPH"
        fi
        ;;
```

## Error Handling

The existing `do_push` function handles failures:
- Checks if there are commits to push (no-op if nothing to push)
- Retries 3 times with 60s delay (configurable via `MAX_PUSH_RETRIES`, `PUSH_RETRY_DELAY`)
- Logs failures and sends error notifications
- If push fails, next successful commit will push all accumulated changes

## Deployment

Existing installations just need `make install` to update the script. No plist regeneration required.
