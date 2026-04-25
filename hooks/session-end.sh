#!/usr/bin/env bash
# session-end.sh — ZeroDB Memory auto-persist hook
# Fires on Stop event. Signals Claude to extract and store session memories.
# Refs #3

set -euo pipefail

# Check if auto-persist is disabled
if [ "${ZERODB_AUTOPERSIST:-on}" = "off" ]; then
  exit 0
fi

# Check if ZeroDB API key is configured
if [ -z "${ZERODB_API_KEY:-}" ]; then
  # Silently skip — user hasn't authenticated yet
  exit 0
fi

# Detect current project from git remote
PROJECT=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$REMOTE" ]; then
    # Normalize: strip protocol, strip .git, lowercase
    # Handles: git@github.com:org/repo.git and https://github.com/org/repo.git
    PROJECT=$(echo "$REMOTE" \
      | sed 's|^https\?://||' \
      | sed 's|^git@||' \
      | sed 's|:|/|' \
      | sed 's|\.git$||' \
      | sed 's|.*github\.com/||' \
      | sed 's|.*gitlab\.com/||' \
      | sed 's|.*bitbucket\.org/||' \
      | tr '[:upper:]' '[:lower:]')
  fi
fi

# Read hook input (Claude Code passes event context via stdin)
INPUT=$(cat 2>/dev/null || echo "{}")

# Output the trigger payload for Claude to act on.
# Claude Code's Stop hook output is surfaced to Claude, which will then
# use the zerodb-memory-guide skill to run the actual memory extraction
# via zerodb_store_memory MCP tool calls.
cat <<EOF
{
  "zerodb_trigger": "session_end",
  "project": "${PROJECT:-unknown}",
  "autopersist_mode": "${ZERODB_AUTOPERSIST:-on}",
  "instruction": "Extract and store key memories from this session using zerodb_store_memory. Follow the zerodb-memory-guide skill instructions. Store at most 20 memories. Skip if the session had fewer than 5 meaningful exchanges."
}
EOF
