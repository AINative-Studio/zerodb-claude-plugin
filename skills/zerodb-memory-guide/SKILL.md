---
description: Core instructions for how Claude should use ZeroDB memory tools proactively throughout a session
---

You have access to ZeroDB persistent memory tools via the `zerodb-memory` MCP server. Use them proactively — memory is the foundation of continuity across sessions.

## Available MCP tools

| Tool | Purpose |
|---|---|
| `zerodb_store_memory` | Store a fact/observation permanently |
| `zerodb_search_memory` | Keyword search across stored memories |
| `zerodb_semantic_search` | Vector similarity search (preferred for recall) |
| `zerodb_get_context` | Get a context bundle for a project/session |
| `zerodb_embed_text` | Embed text for custom similarity queries |
| `zerodb_clear_session` | Clear session-scoped memories |

## Project identity

Always identify the current project before storing or recalling memories:

```bash
git remote get-url origin 2>/dev/null
```

Normalize to `org/repo` lowercase (strip `.git`, strip protocol prefix). Use `unknown` if not in a git repo.

## Auto-recall (session start)

At the start of each session:
1. Detect the project via git remote.
2. Call `zerodb_get_context` with the project ID to load stored memories.
3. Also call `zerodb_semantic_search` using the user's first message as the query, limit 8, to surface the most relevant memories.
4. Inject recalled memories as context before your first response.
5. Announce: "I've loaded N memories for [org/repo]." — or stay silent if 0 memories.
6. Only run recall ONCE per session.

Check `ZERODB_AUTORECALL` env var — if set to `off`, skip auto-recall.

## Auto-persist (session end)

When the session is ending (Stop hook fires), extract and store key facts using `zerodb_store_memory`.

### What TO store
- Architecture decisions made this session
- Bugs found and their root causes or fixes
- Conventions or preferences the user established or corrected you on
- File/module ownership learned ("X owns Y")
- In-progress work and natural next steps
- Commands, ports, URLs, or config patterns discussed
- Things you got wrong and were corrected on — especially important

### What NOT to store
- API keys, passwords, tokens, secrets of any kind
- PII (emails, phone numbers, personal data)
- Raw file contents or large code blocks
- Generic facts that are obvious from reading the code
- Temporary state that won't matter next session

### Memory format
Each memory should be:
- A single, standalone fact (not dependent on session context to understand)
- Concise (1-2 sentences max)
- Tagged with type: `architecture` | `convention` | `bug` | `ownership` | `in-progress` | `correction`
- Tagged with project: `org/repo`
- Tagged with date: `YYYY-MM-DD`

### Rate limiting
Store at most 20 memories per session. Prioritize corrections and architectural decisions over in-progress notes.

Check `ZERODB_AUTOPERSIST` env var:
- `off` — skip auto-persist entirely
- `review` — present extracted memories to user for approval before storing
- `on` (default) — store automatically

## /remember command
When user runs `/remember <text>`:
1. Parse into a structured memory fact.
2. Assign type based on content.
3. Call `zerodb_store_memory` with project, type, date metadata.
4. Confirm: "Stored: [one-line summary]"

## /recall command
When user runs `/recall <query>`:
1. Call `zerodb_semantic_search` with the query.
2. Filter to current project (or all if no project results).
3. Present ranked by relevance with type tags.

## /forget command
When user runs `/forget <query>`:
1. Extract the search query (everything after `/forget`). Detect flags:
   - `--all` — mass delete all memories for the current project (nuclear option)
   - `--type <type>` — filter results to a specific memory type before presenting
2. Detect current project via `git remote get-url origin 2>/dev/null`, normalized to `org/repo` lowercase.
3. Call `zerodb_semantic_search` with the query, limit 20. Filter to current project (`metadata.project`).
4. If no matches found: `No memories found matching '[query]'.` — stop.
5. Present numbered matches for confirmation:
   ```
   Found 2 memories matching 'old staging URL':

   1. [convention] Staging URL is staging.ainative.studio — use this for QA testing
      Stored: 2026-03-15

   2. [architecture] Old staging environment runs on Heroku at app-xyz.herokuapp.com
      Stored: 2026-02-01

   Delete these? Type the numbers to delete (e.g. "1,2"), "all", or "cancel"
   ```
6. Wait for user response:
   - Specific numbers: delete only those memories
   - "all": delete all listed matches
   - "cancel" or anything else: `Cancelled — no memories deleted.`
7. Call the appropriate ZeroDB delete/clear tool, then confirm: `Deleted N memories.`

### Mass delete (--all flag)
If user runs `/forget --all`:
1. Get total memory count via `zerodb_search_memory` with a broad query.
2. Warn: `⚠️  This will permanently delete ALL N memories for [org/repo]. Type DELETE (all caps) to confirm, or anything else to cancel.`
3. Only proceed if the user's next message is exactly `DELETE`.
4. Call `zerodb_clear_session` or equivalent bulk clear.
5. Confirm: `Cleared all N memories for [org/repo].` — or `Cancelled — all memories preserved.`

### Error handling
- If ZeroDB MCP tools are unavailable: `ZeroDB memory is not connected. Check your ZERODB_API_KEY and try again.`
- If not in a git repo: use project = `unknown`, still proceed with search across all memories.

## Privacy — non-negotiable
- NEVER store secrets, credentials, or PII regardless of what the user asks.
- If user asks to remember a secret: "I can't store credentials in memory for security reasons. Use a secrets manager or .env file instead."
