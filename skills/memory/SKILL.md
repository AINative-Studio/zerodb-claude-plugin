---
description: Manage ZeroDB memory settings, browse stored memories, and configure auto-persist/recall
---

The user is running the `/memory` command with a subcommand. Parse the subcommand and act accordingly.

## Subcommands

### `/memory list`
List all memories for the current project, paginated (20 per page).
- Call `zerodb_search_memory` with an empty/broad query, current project filter.
- Display as numbered list with type tags and truncated content.
- Show: `Page 1 of N — /memory list --page 2 for more`

### `/memory search <query>`
Semantic search across memories. Equivalent to `/recall <query>` — delegate to that skill.

### `/memory stats`
Show memory statistics for the current project:
- Total memories stored
- Breakdown by type (architecture: N, convention: N, bug: N, ...)
- Last sync date
- ZeroDB project ID in use
- Auto-persist status: on/off/review
- Auto-recall status: on/off

### `/memory autopersist [on|off|review]`
Toggle auto-persist mode:
- `on` — automatically store memories at session end (default after onboarding)
- `off` — disable auto-persist; user must use /remember manually
- `review` — show extracted memories for approval before storing
Store preference by advising user to set `ZERODB_AUTOPERSIST=on|off|review` in their environment.

### `/memory autorecall [on|off]`
Toggle auto-recall at session start.
Store preference by advising user to set `ZERODB_AUTORECALL=on|off` in their environment.

### `/memory clear`
Wipe all memories for the current project. Requires double confirmation — delegate to the `/forget --all` flow.

### `/memory export`
Export memories as Markdown or JSON.
- Default: Markdown, grouped by type
- `--format json` — raw JSON array
- `--format claudemd` — generates a CLAUDE.md skeleton from memories (future Phase 3 feature)
Present output inline, then ask if user wants to write to a file.

### `/memory team setup`
(Phase 4) Connect to a shared team ZeroDB project. Placeholder — inform user this feature is coming in Phase 4.

### No subcommand / help
Show available subcommands with one-line descriptions.
