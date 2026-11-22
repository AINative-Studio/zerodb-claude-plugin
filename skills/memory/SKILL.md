---
description: Manage ZeroDB memory — browse, search, export, configure auto-persist and auto-recall
---

The user is running the `/memory` command. Parse the subcommand (first word after `/memory`) and act accordingly.

## Subcommand: `/memory list [--page N] [--type <type>] [--team] [--personal]`

List stored memories for the current project.

1. Detect current project via `git remote get-url origin 2>/dev/null`, normalize to `org/repo`.
2. Call `zerodb_search_memory` with a broad/empty query, filtered to current project (personal by default).
3. If a team project is configured (`.claude/zerodb.json` → `teamProjectId`) and neither `--personal` nor `--team` was passed, also fetch team memories and merge both lists, newest-first, each row labeled `[team]` or `[personal]`:
   ```
   Memories for ainative-studio/core (Page 1 of 3)

    1. [personal] [architecture] Database connections must go through PgBouncer on port 6432, not 5432
       2026-04-10
    2. [team]     [convention]   All API endpoints must include Refs #<issue> in commit messages
       2026-04-08
    3. [personal] [ownership]    Payments module owned by Sarah — requires sign-off before refactoring
       2026-04-05
   ...

   /memory list --page 2 for more
   ```
   When no team project is configured, omit the `[team]`/`[personal]` labels entirely — show plain rows like the solo-user example that follows.
4. `--team` restricts to the team project only (error `No team project set. Run /memory team setup` if none configured). `--personal` restricts to the personal project only, even when a team project exists.
5. Support `--type <type>` filter: only show memories of that type.
6. If no memories: `No memories stored for [org/repo] yet. Use /remember to add some.`

## Subcommand: `/memory search <query>`

Semantic search. Equivalent to `/recall <query>` — run that skill's logic and present results identically.

## Subcommand: `/memory stats`

Show memory statistics for the current project.

1. Detect current project.
2. Call `zerodb_get_context` and `zerodb_search_memory` to gather counts, against the personal project.
3. Check for a team project (`.claude/zerodb.json` → `teamProjectId`). If present, gather its counts too and show both.
4. Display (solo user, no team project):
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
   Or, with a team project configured:
   ```
   ZeroDB Memory Stats — ainative-studio/core

   Personal: 31 memories (proj_abc123)
   Team:     14 memories (proj_team_xyz789)

   Last stored:     2026-04-24
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

## Subcommand: `/memory team setup [<team-project-id>]`

Connect this repo to a shared team ZeroDB project so memories captured by
any teammate are visible to the whole team. Writes `.claude/zerodb.json`
at the repo root, which is meant to be **committed to version control** so
every teammate's Claude Code picks up the same team project automatically.

1. Determine the repo root: `git rev-parse --show-toplevel 2>/dev/null`. If
   not in a git repo: `Team memory requires a git repository (so .claude/zerodb.json can be shared via version control).` — stop.
2. Check for an existing `.claude/zerodb.json` with a `teamProjectId` already set.
   - If one exists and the user didn't pass a new ID: show the current team
     project ID and ask `A team project is already configured (<id>). Replace it? (y/n)`. Stop if the user declines.
3. If the user provided `<team-project-id>` as an argument, use it directly.
   Otherwise, ask: `Enter the ZeroDB team project ID (create one at the AINative dashboard, or ask your team admin for the existing one):` and wait for their reply.
4. Verify the ID resolves to a real, accessible project — call the same
   project-resolution the MCP server itself uses (e.g. `zerodb_get_context`
   with that project ID) and confirm it doesn't error. If it does:
   `Couldn't verify project <id> — check the ID and that your ZERODB_API_KEY has access to it.` — stop, don't write the config.
5. Write `.claude/zerodb.json`:
   ```json
   {
     "teamProjectId": "<verified-id>"
   }
   ```
   Preserve a `personalProjectId` key already present in the file (from a
   prior setup), if any — only add/replace `teamProjectId`.
6. Confirm to the user:
   ```
   Team memory connected: <id>

   .claude/zerodb.json has been created/updated. Commit this file so your
   whole team picks up shared memory automatically:

     git add .claude/zerodb.json
     git commit -m "Connect team ZeroDB memory"

   Use /remember --team <text> to store a memory for the whole team, and
   /recall (or /memory list) will now include team memories alongside
   your personal ones.
   ```

### Removing team memory (`/memory team setup --remove`)
1. If `.claude/zerodb.json` doesn't exist or has no `teamProjectId`: `No team project is configured for this repo.` — stop.
2. Remove the `teamProjectId` key, preserving any `personalProjectId` entry. If the file would then be empty (`{}`), delete the file entirely instead of leaving an empty JSON object around.
3. Confirm: `Team memory disconnected. (Existing team memories are not deleted — only this repo's local link to them was removed.) Remember to commit this change: git add .claude/zerodb.json && git commit -m "Disconnect team ZeroDB memory"` (or, if the file was deleted, mention `git rm .claude/zerodb.json` instead).

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
  /memory team setup        Connect this repo to a shared team project
  /memory team setup --remove   Disconnect this repo's team project

Use /remember, /recall, and /forget for quick memory operations.
Use /remember --team and /recall --team once a team project is connected.
```
