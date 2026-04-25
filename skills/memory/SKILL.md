---
description: Manage ZeroDB memory — browse, search, export, configure auto-persist and auto-recall
---

The user is running the `/memory` command. Parse the subcommand (first word after `/memory`) and act accordingly.

## Subcommand: `/memory list [--page N] [--type <type>]`

List stored memories for the current project.

1. Detect current project via `git remote get-url origin 2>/dev/null`, normalize to `org/repo`.
2. Call `zerodb_search_memory` with a broad/empty query, filtered to current project.
3. Display paginated results (20 per page):
   ```
   Memories for ainative-studio/core (Page 1 of 3)

    1. [architecture] Database connections must go through PgBouncer on port 6432, not 5432
       2026-04-10
    2. [convention]   All API endpoints must include Refs #<issue> in commit messages
       2026-04-08
    3. [ownership]    Payments module owned by Sarah — requires sign-off before refactoring
       2026-04-05
   ...

   /memory list --page 2 for more
   ```
4. Support `--type <type>` filter: only show memories of that type.
5. If no memories: `No memories stored for [org/repo] yet. Use /remember to add some.`

## Subcommand: `/memory search <query>`

Semantic search. Equivalent to `/recall <query>` — run that skill's logic and present results identically.

## Subcommand: `/memory stats`

Show memory statistics for the current project.

1. Detect current project.
2. Call `zerodb_get_context` and `zerodb_search_memory` to gather counts.
3. Display:
   ```
   ZeroDB Memory Stats — ainative-studio/core

   Total memories:  31
   ├─ architecture:  8
   ├─ convention:   12
   ├─ bug:           4
   ├─ ownership:     3
   ├─ in-progress:   2
   └─ correction:    2

   Last stored:     2026-04-24
   ZeroDB project:  proj_abc123
   Auto-persist:    on
   Auto-recall:     on
   ```

## Subcommand: `/memory autopersist [on|off|review]`

Toggle auto-persist mode.

- `on` — automatically store memories at session end
- `off` — disable; user must use /remember manually
- `review` — show extracted memories for approval before storing
- No argument — show current setting

Instruct the user to set the env var:
```
To persist this setting, add to your shell profile:
export ZERODB_AUTOPERSIST=on   # or off, or review
```

Confirm: `Auto-persist set to: on`

## Subcommand: `/memory autorecall [on|off]`

Toggle auto-recall at session start.

- `on` — inject relevant memories at session start
- `off` — disable auto-recall
- No argument — show current setting

Instruct the user to set the env var:
```
export ZERODB_AUTORECALL=on   # or off
```

Confirm: `Auto-recall set to: on`

## Subcommand: `/memory clear`

Wipe all memories for the current project. Delegates to the `/forget --all` flow — apply the same double-confirmation (user must type DELETE) before proceeding.

## Subcommand: `/memory export [--format json|markdown|claudemd] [--output <filename>]`

Export all memories for the current project.

1. Detect current project.
2. Fetch all memories via `zerodb_search_memory`.
3. Format based on `--format` flag (default: markdown):

**markdown** (default):
```markdown
# ZeroDB Memories — ainative-studio/core
Exported: 2026-04-24

## Architecture
- Database connections must go through PgBouncer on port 6432, not 5432
- Railway internal DNS unreachable from Kong — always use public URLs

## Conventions
- All API endpoints must include Refs #<issue> in commit messages
...
```

**json**: Raw JSON array of memory objects.

**claudemd**: Full CLAUDE.md generation from stored memories — **delegate entirely to the `claudemd-export` skill** (`skills/claudemd-export/SKILL.md`). That skill handles:
- Broad semantic retrieval across all 6 memory types (up to 200 memories)
- Deduplication of semantically equivalent facts
- Structured CLAUDE.md output with standard sections (Architecture, Conventions, File Ownership, Active Work, Known Issues, Important Corrections)
- Update vs. create flow with diff preview and merge mode
- `--dry-run` support

Pass all flags through to the delegated skill unchanged (e.g. `--output CLAUDE.md`, `--dry-run`).

4. If `--output <filename>` provided: write to that file and confirm `Exported N memories to <filename>`.
5. Otherwise: display inline and ask `Write to file? (enter filename or press Enter to skip)`.

## Subcommand: `/memory team setup` (Phase 4 — not yet available)

Inform the user:
```
Team shared memory is coming in Phase 4. 
Track progress: https://github.com/AINative-Studio/zerodb-claude-plugin/issues/19
```

## No subcommand / unknown subcommand

Show help:
```
ZeroDB Memory — available commands:

  /memory list              Browse stored memories for this project
  /memory search <query>    Semantic search across memories
  /memory stats             Memory count, types, and configuration
  /memory autopersist       Configure auto-persist (on/off/review)
  /memory autorecall        Configure auto-recall (on/off)
  /memory export            Export memories as Markdown, JSON, or CLAUDE.md
  /memory clear             Delete all memories for this project
  /memory team setup        (Phase 4) Connect shared team memory

Use /remember, /recall, and /forget for quick memory operations.
```
