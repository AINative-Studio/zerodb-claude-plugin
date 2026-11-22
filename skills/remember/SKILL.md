---
description: Store a memory in ZeroDB for future Claude Code sessions
---

The user wants to store a memory permanently in ZeroDB so it can be recalled in future sessions.

## Steps

1. Check for a `--team` flag at the start of the input. If present, strip it
   from the text before parsing — the rest of the steps are identical except
   for which project the memory is stored to (see "Team mode" below).
2. Parse the user's input into a structured, concise memory fact.
3. Determine the memory type from the content:
   - `architecture` — system design decisions, tech choices, infrastructure patterns
   - `convention` — coding standards, workflow rules, preferences the user has established
   - `bug` — bugs found and their root causes or fixes
   - `ownership` — who owns what (modules, services, domains)
   - `in-progress` — work currently underway, next steps, blockers
   - `correction` — something Claude got wrong and was corrected on
4. Detect the current project using git remote (run `git remote get-url origin 2>/dev/null`), normalized to `org/repo` lowercase. Use `unknown` if not in a git repo.
5. Call `zerodb_store_memory` with:
   - `content`: the concise memory text
   - `metadata`: `{ "project": "<org/repo>", "type": "<type>", "date": "<YYYY-MM-DD>" }`
   - `project_id`: the personal project's ID (default) or the team project's ID (`--team` mode)
6. Confirm to the user: "Stored: [one-line summary of what was saved]" (personal) or "Stored to team memory: [one-line summary]" (`--team`)

## Team mode (`/remember --team <text>`)

1. Check whether this repo has `.claude/zerodb.json` with a `teamProjectId`
   (repo root = `git rev-parse --show-toplevel`). See the
   `zerodb-memory-guide` skill's "Team shared memory" section for the
   schema and resolution rules.
2. If no team project is configured: reply exactly
   `No team project set. Run /memory team setup` and stop — do not store
   the memory anywhere (not even personally), since the user explicitly
   asked for team storage.
3. Otherwise, follow the normal steps above but target `teamProjectId`
   instead of the personal project, and add `metadata.author` (the
   storing user's git `user.name` or `user.email`) so teammates can see
   who contributed each team memory.

## Privacy rules (mandatory)
- NEVER store: API keys, passwords, tokens, secrets, PII, or raw file contents
- ONLY store: facts, decisions, patterns, observations, and references to things (not the things themselves)

## Examples

User: `/remember Sarah owns the payments module — never refactor without her sign-off`
→ type: ownership, content: "payments module owned by Sarah — requires her sign-off before refactoring"

User: `/remember Railway internal DNS doesn't work from Kong, always use public URLs`
→ type: architecture, content: "Railway internal DNS unreachable from Kong — always use public Railway URLs for upstream config"

User: `/remember we use PgBouncer on port 6432, never connect directly to 5432`
→ type: convention, content: "Database connections must go through PgBouncer on port 6432, not direct Postgres on 5432"

User: `/remember --team we deploy from the release branch only, never main directly` (team project configured)
→ stored to team project, type: convention, metadata.author set, confirmed with "Stored to team memory: ..."

User: `/remember --team anything` (no team project configured)
→ "No team project set. Run /memory team setup" — nothing stored
