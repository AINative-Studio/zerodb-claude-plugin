---
description: Remove stored memories from ZeroDB by searching for matches and confirming before deletion
---

The user wants to delete one or more memories from ZeroDB.

## Parse the user input

Everything after `/forget` is the search query. Special flags:
- `--all` — mass delete all memories for the current project (nuclear option)
- `--type <type>` — filter matches to a specific memory type before presenting

## Standard flow (no --all flag)

1. Extract the search query.
2. Detect current project: run `git remote get-url origin 2>/dev/null`, normalize to `org/repo` lowercase.
3. Call `zerodb_semantic_search` with the query, limit 20.
4. Filter results to current project (`metadata.project`).
5. If no matches:
   ```
   No memories found matching '[query]'.
   ```
   Stop here.
6. Present matches numbered for confirmation:
   ```
   Found 2 memories matching 'old staging URL':

   1. [convention] Staging URL is staging.ainative.studio — use this for QA testing
      Stored: 2026-03-15

   2. [architecture] Old staging environment runs on Heroku at app-xyz.herokuapp.com
      Stored: 2026-02-01

   Delete these? Type the numbers to delete (e.g. "1,2"), "all", or "cancel"
   ```
7. Wait for user response:
   - Specific numbers (e.g. "1" or "1,2"): delete only those memories
   - "all": delete all listed matches
   - "cancel" or anything else: abort with "Cancelled — no memories deleted."
8. Call the appropriate ZeroDB delete/clear tool for each confirmed memory.
9. Confirm: `Deleted N memories.`

## Mass delete (--all flag)

If user runs `/forget --all`:
1. Detect current project.
2. Get total memory count for the project via `zerodb_search_memory` with broad query.
3. Warn the user:
   ```
   ⚠️  This will permanently delete ALL N memories for [org/repo].
   Type DELETE (all caps) to confirm, or anything else to cancel.
   ```
4. Only proceed if the user's next message is exactly `DELETE`.
5. Call `zerodb_clear_session` or equivalent bulk clear for the project.
6. Confirm: `Cleared all N memories for [org/repo].`
7. If not confirmed: `Cancelled — all memories preserved.`

## Error handling

- If ZeroDB MCP tools are unavailable: `ZeroDB memory is not connected. Check your ZERODB_API_KEY and try again.`
- If not in a git repo: use project = `unknown`, still proceed with search across all memories.

## Examples

```
/forget old staging URL
/forget the celery migration note — it shipped last week
/forget --type convention anything about port 5432
/forget --all
```
