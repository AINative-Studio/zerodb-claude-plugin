# ZeroDB Memory — Claude Code Plugin

Persistent cross-session memory for Claude Code, powered by [ZeroDB](https://ainative.studio/products/zerodb).

Claude Code loses all context at the end of every session. This plugin fixes that. It automatically stores what Claude learns during a session and recalls it the next time you start working — architecture decisions, bug discoveries, conventions, code ownership, and in-progress work.

## Install

```shell
# From the official Claude Code marketplace
/plugin install zerodb-memory@claude-plugins-official

# Direct from GitHub (no marketplace needed)
/plugin install github:AINative-Studio/zerodb-claude-plugin
```

## Auth

Set your ZeroDB API key before the first session:

```bash
export ZERODB_API_KEY=your_api_key_here
export ZERODB_PROJECT_ID=your_project_id  # optional, auto-detected if omitted
```

No account? [Sign up free](https://ainative.studio/signup?ref=claude-plugin) — 500 credits included, no card required.

## How it works

**At session start:** Claude automatically loads memories for the current project and announces what was recalled.

**At session end:** Claude extracts key facts from the conversation — decisions made, bugs found, conventions established — and stores them in ZeroDB.

**Anytime:**

```shell
/remember Sarah owns the payments module — get her sign-off before refactoring
/recall how do we connect to the database
/forget old staging URL
/memory stats
```

## Slash commands

| Command | Description |
|---|---|
| `/remember <text>` | Manually store a memory |
| `/recall <query>` | Search memories semantically |
| `/forget <query>` | Remove matching memories (with confirmation) |
| `/memory list` | Browse all memories for this project |
| `/memory stats` | Memory count, types, last sync |
| `/memory autopersist [on\|off\|review]` | Toggle auto-persist |
| `/memory autorecall [on\|off]` | Toggle auto-recall |
| `/memory export` | Export memories as Markdown or JSON |
| `/memory clear` | Wipe all memories for this project |

## Configuration

| Env var | Default | Description |
|---|---|---|
| `ZERODB_API_KEY` | — | Required. Your ZeroDB API key |
| `ZERODB_PROJECT_ID` | auto | ZeroDB project ID (auto-detected from git remote) |
| `ZERODB_AUTOPERSIST` | `on` | Auto-persist mode: `on`, `off`, or `review` |
| `ZERODB_AUTORECALL` | `on` | Auto-recall on session start: `on` or `off` |

## Privacy

- Memories are facts and observations — never raw file contents, secrets, or credentials
- Stored in your ZeroDB account, not shared with anyone
- Use `/memory clear` to wipe all memories for a project at any time

## Credits

Memory operations bill to your ZeroDB account:

| Operation | Credits |
|---|---|
| Store memory | 1 credit |
| Semantic search | 2 credits |
| Get context bundle | 3 credits |

Average session: ~25 credits (~$0.25). [See pricing](https://ainative.studio/pricing).

## Documentation

Full docs: [docs.ainative.studio/claude-plugin](https://docs.ainative.studio/claude-plugin)

## License

MIT — [AINative Studio](https://ainative.studio)
