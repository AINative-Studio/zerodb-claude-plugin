#!/usr/bin/env bash
# session-start.sh — ZeroDB Memory auto-recall hook
# Fires on PreToolUse. Injects relevant memories at session start.
# Runs only once per session via a session-scoped sentinel file.
# Refs #4

set -euo pipefail

# Check if auto-recall is disabled
if [ "${ZERODB_AUTORECALL:-on}" = "off" ]; then
  exit 0
fi

# Check if ZeroDB API key is configured
if [ -z "${ZERODB_API_KEY:-}" ]; then
  exit 0
fi

# Session sentinel — only run once per Claude Code session.
# Claude Code sets CLAUDE_SESSION_ID when available.
SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%Y%m%d%H)}"
SENTINEL_DIR="${TMPDIR:-/tmp}/zerodb-sessions"
SENTINEL_FILE="${SENTINEL_DIR}/${SESSION_ID}.recalled"

mkdir -p "$SENTINEL_DIR"

if [ -f "$SENTINEL_FILE" ]; then
  # Already ran recall this session — exit silently
  exit 0
fi

# Mark as recalled for this session
touch "$SENTINEL_FILE"

# Source project identity library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/project-id.sh
source "${SCRIPT_DIR}/../lib/project-id.sh"
PROJECT=$(zerodb_get_project_id)

# Output trigger payload. Claude will call zerodb_get_context and
# zerodb_semantic_search via MCP, then inject memories as context.
cat <<EOF
{
  "zerodb_trigger": "session_start",
  "project": "${PROJECT:-unknown}",
  "instruction": "Load memories for this project using zerodb_get_context and zerodb_semantic_search. Inject the most relevant memories as context before responding. Announce how many memories were loaded, or stay silent if zero. Follow the zerodb-memory-guide skill instructions."
}
EOF
