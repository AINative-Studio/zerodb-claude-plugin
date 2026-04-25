---
description: Store a memory in ZeroDB for future Claude Code sessions
---

The user wants to store a memory permanently in ZeroDB so it can be recalled in future sessions.

## Steps

1. Parse the user's input into a structured, concise memory fact.
2. Determine the memory type from the content:
   - `architecture` — system design decisions, tech choices, infrastructure patterns
   - `convention` — coding standards, workflow rules, preferences the user has established
   - `bug` — bugs found and their root causes or fixes
   - `ownership` — who owns what (modules, services, domains)
   - `in-progress` — work currently underway, next steps, blockers
   - `correction` — something Claude got wrong and was corrected on
3. Detect the current project using git remote (run `git remote get-url origin 2>/dev/null`), normalized to `org/repo` lowercase. Use `unknown` if not in a git repo.
4. Call `zerodb_store_memory` with:
   - `content`: the concise memory text
   - `metadata`: `{ "project": "<org/repo>", "type": "<type>", "date": "<YYYY-MM-DD>" }`
5. Confirm to the user: "Stored: [one-line summary of what was saved]"

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
