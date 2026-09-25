#!/usr/bin/env bash
# session-start.sh — ZeroDB Memory auto-recall hook
# Fires on SessionStart. Injects relevant memories at session start.
# The sentinel file below is now redundant (SessionStart already fires
# exactly once per session) but left as defense-in-depth.
# Refs #4

set -euo pipefail

# Check if auto-recall is disabled
if [ "${ZERODB_AUTORECALL:-on}" = "off" ]; then
  exit 0
fi

SCRIPT_DIR_EARLY="$(cd "$(dirname "$0")" && pwd)"

# Resolve credentials the same way the MCP server does (env, persisted
# cache, sibling tool, or auto-provisioned trial) so a fresh install with
# no ZERODB_API_KEY exported still gets a working recall + a claim-link
# announcement instead of silently doing nothing.
if [ -z "${ZERODB_API_KEY:-}" ]; then
  RESOLVED=$("${SCRIPT_DIR_EARLY}/../lib/ensure-credentials.sh" 2>/dev/null) || exit 0
  ZERODB_API_KEY=$(printf '%s\n' "$RESOLVED" | sed -n 's/^ZERODB_API_KEY=//p')
  [ -n "$ZERODB_API_KEY" ] || exit 0
fi

CLAIM_URL=""
CACHE_DIR_EARLY="${TMPDIR:-/tmp}/zerodb-status"
if [ -f "${CACHE_DIR_EARLY}/status.json" ] && grep -q '"state": *"trial_provisioned"' "${CACHE_DIR_EARLY}/status.json" 2>/dev/null; then
  CLAIM_URL=$(sed -n 's/.*"claim_url": *"\([^"]*\)".*/\1/p' "${CACHE_DIR_EARLY}/status.json")
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

# Update status cache — mark as synced after recall completes
CACHE_DIR="${TMPDIR:-/tmp}/zerodb-status"
mkdir -p "$CACHE_DIR"
echo '{"count": null, "state": "synced", "last_updated": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "${CACHE_DIR}/status.json"

# Output trigger payload. Claude will call zerodb_get_context and
# zerodb_semantic_search via MCP, then inject memories as context.
if [ -n "$CLAIM_URL" ]; then
  INSTRUCTION="A free trial ZeroDB project was just auto-provisioned for you — no signup needed to start using memory. It expires in 72 hours unless claimed. Tell the user once, briefly: memory is active, and they can claim this project permanently at ${CLAIM_URL}. Then load memories for this project using zerodb_get_context and zerodb_semantic_search. Follow the zerodb-memory-guide skill instructions."
else
  INSTRUCTION="Load memories for this project using zerodb_get_context and zerodb_semantic_search. Inject the most relevant memories as context before responding. Announce how many memories were loaded, or stay silent if zero. Follow the zerodb-memory-guide skill instructions."
fi

cat <<EOF
{
  "zerodb_trigger": "session_start",
  "project": "${PROJECT:-unknown}",
  "instruction": "${INSTRUCTION}"
}
EOF
