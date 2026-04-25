Show HN: ZeroDB Memory — persistent cross-session memory for Claude Code

Claude Code forgets everything at the end of every session. We built a plugin that fixes that.

ZeroDB Memory is an open-source Claude Code plugin that:
- Auto-captures key facts at session end (architecture decisions, bugs found, conventions, code ownership)
- Auto-recalls relevant context at session start using semantic search
- Adds /remember, /recall, /forget, /memory slash commands

Install:
/plugin install github:AINative-Studio/zerodb-claude-plugin

How it works: At session end, a Stop hook fires and Claude extracts key facts from the conversation, storing them in ZeroDB (our vector + graph memory API). At session start, a PreToolUse hook fires, loads memories for the current git repo, and injects the most relevant ones ranked by semantic similarity to your first message.

The plugin is free to install. Memory ops bill to your ZeroDB account — 500 free credits on signup (~20 sessions), then $9/mo for 5,000 credits.

We also added /memory export --format claudemd which generates a CLAUDE.md from your accumulated memories automatically.

Repo: github.com/AINative-Studio/zerodb-claude-plugin
Docs: docs.ainative.studio/guides/claude-plugin
