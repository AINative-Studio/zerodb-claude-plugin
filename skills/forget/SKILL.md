---
description: Remove stored memories from ZeroDB
---

The user wants to delete one or more memories from ZeroDB.

## Steps

1. Extract the search query from the user's input (everything after `/forget`).
2. Check for `--all` flag — if present, handle mass delete flow (see below).
3. Call `zerodb_semantic_search` with the query, limit 10.
4. Present matching memories for confirmation:

```
Found 2 memories matching 'old staging URL':

1. [convention] Staging URL is staging.ainative.studio — use this for QA testing
2. [architecture] Old staging environment runs on Heroku at app-xyz.herokuapp.com

Delete these? (yes/no)
```

5. If user confirms: call the appropriate delete/clear tool for each memory ID.
6. Confirm: `Deleted 2 memories.`
7. If no matches: `No memories found matching '[query]'.`

## Mass delete (--all)

If user runs `/forget --all`:
1. Ask: `This will delete ALL memories for project [org/repo]. Type 'DELETE' to confirm.`
2. Only proceed if user types exactly `DELETE`.
3. Call `zerodb_clear_session` or equivalent bulk clear for the project.
4. Confirm: `Cleared all memories for [org/repo].`

## Examples

`/forget old staging URL`
`/forget the celery migration note — it shipped`
`/forget --all` (nuclear option, double confirmed)
