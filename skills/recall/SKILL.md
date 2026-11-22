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
4. Check whether this repo has a team project configured (`.claude/zerodb.json` → `teamProjectId`; see the `zerodb-memory-guide` skill's "Team shared memory" section). If so, also call `zerodb_semantic_search` with the same query against the team project, and merge both result sets by relevance rather than listing personal results then team results (or vice versa).
5. Filter results to those matching the current project (check `metadata.project`), or show all if no project match found.
6. Present results ranked by relevance. Label each result `[team]` or `[personal]` only when a team project is configured — a solo user with no team project sees plain, unlabeled results:

```
Found N memories:

[personal] [architecture] Railway internal DNS unreachable from Kong — always use public Railway URLs
[team]     [convention]   Deploy from the release branch only, never main directly
[personal] [ownership]    Payments module owned by Sarah — requires sign-off before refactoring
```

7. If no results: `No memories found for '[query]'. Use /remember to store new memories.`

## Optional filters (parse from user input if present)
- `--type <type>` — filter by memory type (architecture, convention, bug, ownership, in-progress, correction)
- `--all` — search across all projects, not just current one
- `--team` — search only the team project (error with `No team project set. Run /memory team setup` if none is configured)
- `--personal` — search only the personal project, skipping team results even if a team project is configured

## Examples

`/recall how do we connect to the database`
`/recall who owns the auth module`
`/recall what port does postgres use`
`/recall --type bug recent issues we found`
`/recall --team how do we handle on-call rotation`
