---
description: Search and surface memories from ZeroDB for the current project
---

The user wants to recall stored memories relevant to their query.

## Steps

1. Extract the search query from the user's input (everything after `/recall`).
2. Detect the current project: run `git remote get-url origin 2>/dev/null`, normalize to `org/repo` lowercase.
3. Call `zerodb_semantic_search` with:
   - `query`: the user's search text
   - `limit`: 10
4. Filter results to those matching the current project (check `metadata.project`), or show all if no project match found.
5. Present results ranked by relevance:

```
Found N memories:

[architecture] Railway internal DNS unreachable from Kong — always use public Railway URLs
[convention]   Database connections must go through PgBouncer on port 6432, not 5432
[ownership]    Payments module owned by Sarah — requires sign-off before refactoring
```

6. If no results: `No memories found for '[query]'. Use /remember to store new memories.`

## Optional filters (parse from user input if present)
- `--type <type>` — filter by memory type (architecture, convention, bug, ownership, in-progress, correction)
- `--all` — search across all projects, not just current one

## Examples

`/recall how do we connect to the database`
`/recall who owns the auth module`
`/recall what port does postgres use`
`/recall --type bug recent issues we found`
