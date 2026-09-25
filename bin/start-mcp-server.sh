#!/usr/bin/env bash
# bin/start-mcp-server.sh — Launches the ZeroDB memory MCP server with
# resolved credentials, auto-provisioning a free trial project if none
# are configured anywhere (env, prior session, or persisted file).
#
# This exists because Claude Code substitutes a plugin's mcpServers[].env
# ${VAR} placeholders from the launching process's environment ONLY — it
# cannot run a hook or provisioning step first. Wrapping the real command
# here lets us resolve credentials (including auto-provisioning) before
# the MCP server itself ever starts, instead of hard-failing with
# "Missing environment variables" when the user hasn't exported them.
#
# Refs #33

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CREDS=$("${SCRIPT_DIR}/../lib/ensure-credentials.sh" 2>/dev/null) || {
  echo "zerodb-memory: could not resolve or auto-provision ZeroDB credentials." >&2
  echo "Set ZERODB_API_KEY and ZERODB_PROJECT_ID, or check network access to api.ainative.studio." >&2
  exit 1
}

export ZERODB_API_KEY
export ZERODB_PROJECT_ID
ZERODB_API_KEY=$(printf '%s\n' "$CREDS" | sed -n 's/^ZERODB_API_KEY=//p')
ZERODB_PROJECT_ID=$(printf '%s\n' "$CREDS" | sed -n 's/^ZERODB_PROJECT_ID=//p')

exec npx -y ainative-zerodb-memory-mcp@latest
