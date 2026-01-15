# Config Command Design

Add a `config` command to the CLI for viewing and editing configuration.

## Command Structure

```
logseq-sync config                           # Show global config + list graph configs
logseq-sync config show [--graph NAME]       # Same as above, or show specific graph config
logseq-sync config edit [--graph NAME]       # Open config in $EDITOR
logseq-sync config get KEY [--graph NAME]    # Get single value (for scripts)
logseq-sync config set KEY VALUE [--graph NAME]  # Set single value
```

The `--graph` flag is optional on all subcommands. Without it, operations target the global config. With it, they target that graph's config.

## Output Format

`logseq-sync config` (no args):

```
Global config (~/.config/logseq-git-sync/config):
  QUIET_PERIOD=30
  FETCH_INTERVAL=300
  NOTIFY_ON_PUSH=true
  ...

Graphs:
  mylog    ~/.config/logseq-git-sync/graphs/mylog.conf
  work     ~/.config/logseq-git-sync/graphs/work.conf

Use 'logseq-sync config show --graph NAME' to view a graph's config.
Use 'logseq-sync config edit' to modify settings.
```

`logseq-sync config get KEY` returns just the raw value with no decoration (e.g., `30`), making it script-friendly.

## Error Handling

- **No global config file**: Show defaults from template with note "(defaults - no config file exists)"
- **Unknown graph**: `Error: Graph 'foo' not found. Run 'logseq-sync status' to list graphs.`
- **Unknown key on get**: Exit code 1, no output
- **Unknown key on set**: Allow it (users may want custom variables)
- **No $EDITOR**: Fall back to `vi`, then error if not found
- **Edit creates new file**: If global config doesn't exist, create from template first

## Implementation

Changes to `scripts/logseq-sync`:

1. Add `config` to usage text
2. Add functions: `config_show()`, `config_edit()`, `config_get()`, `config_set()`
3. Add helper `get_config_path()` to resolve file based on `--graph` flag
4. Add case in main dispatch for `config` command

~100-150 lines added to existing CLI script.

## Tests

New file `tests/config.bats`:
- `config` shows global settings
- `config show --graph` shows graph-specific settings
- `config get` returns raw value
- `config set` updates value
- `config edit` opens editor (mock $EDITOR)
- Error cases for missing graph, missing key
