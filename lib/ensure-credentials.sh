#!/usr/bin/env bash
# lib/ensure-credentials.sh — Resolve or auto-provision ZeroDB credentials
# for the plugin, independent of the parent shell's exported env vars.
#
# Resolution order (each candidate is verified against the API before use;
# a stale/invalid candidate falls through to the next source instead of
# failing outright):
#   1. ZERODB_API_KEY / ZERODB_PROJECT_ID already in the environment
#   2. Previously persisted credentials at ~/.claude/zerodb-memory/credentials.env
#      (this plugin's own cache — never written by any other tool)
#   3. ~/.zerodb/.env, if present — a sibling convention used by other
#      ZeroDB-auto-provisioning tools (e.g. zerodb-local). Read-only: this
#      script never writes into ~/.zerodb, only the plugin's own directory.
#   4. Auto-provision a free trial project via the public instant-db API
#      and persist the result for future sessions
#
# On success, prints two lines to stdout:
#   ZERODB_API_KEY=<value>
#   ZERODB_PROJECT_ID=<value>
# On failure, prints nothing and exits non-zero.
#
# Refs #33

set -uo pipefail

CRED_DIR="${HOME}/.claude/zerodb-memory"
CRED_FILE="${CRED_DIR}/credentials.env"
SIBLING_ENV_FILE="${HOME}/.zerodb/.env"
PROVISION_URL="https://api.ainative.studio/api/v1/public/instant-db"
VERIFY_URL="https://api.ainative.studio/api/v1/public/api-keys/verify"

# Returns 0 if the given API key verifies against the live API, non-zero
# otherwise (including any network failure — treated as "not usable" so we
# fall through rather than hand the MCP server a key we can't vouch for).
verify_key() {
  local key="$1"
  [ -n "$key" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  local status attempt
  for attempt in 1 2; do
    status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$VERIFY_URL" \
      -H "X-API-Key: ${key}" 2>/dev/null)
    [ "$status" = "200" ] && return 0
    # A gateway timeout/5xx is transient — one quick retry before giving up
    # on an otherwise-untested key. A 401/403 means the key itself is bad;
    # no point retrying that.
    case "$status" in
      5*) sleep 1 ;;
      *) return 1 ;;
    esac
  done
  return 1
}

# 1. Already in the environment — respect it without a network round-trip.
if [ -n "${ZERODB_API_KEY:-}" ] && [ -n "${ZERODB_PROJECT_ID:-}" ]; then
  echo "ZERODB_API_KEY=${ZERODB_API_KEY}"
  echo "ZERODB_PROJECT_ID=${ZERODB_PROJECT_ID}"
  exit 0
fi

# 2. Previously persisted by this plugin.
if [ -f "$CRED_FILE" ]; then
  PERSISTED_KEY=""
  PERSISTED_PROJECT=""
  # shellcheck disable=SC1090
  source "$CRED_FILE"
  PERSISTED_KEY="${ZERODB_API_KEY:-}"
  PERSISTED_PROJECT="${ZERODB_PROJECT_ID:-}"
  if [ -n "$PERSISTED_KEY" ] && [ -n "$PERSISTED_PROJECT" ] && verify_key "$PERSISTED_KEY"; then
    echo "ZERODB_API_KEY=${PERSISTED_KEY}"
    echo "ZERODB_PROJECT_ID=${PERSISTED_PROJECT}"
    exit 0
  fi
  unset ZERODB_API_KEY ZERODB_PROJECT_ID
fi

# 3. A sibling ZeroDB tool may have already provisioned credentials.
if [ -f "$SIBLING_ENV_FILE" ]; then
  SIBLING_KEY=$(sed -n 's/^ZERODB_API_KEY=//p' "$SIBLING_ENV_FILE" | tail -1)
  SIBLING_PROJECT=$(sed -n 's/^ZERODB_PROJECT_ID=//p' "$SIBLING_ENV_FILE" | tail -1)
  if [ -n "$SIBLING_KEY" ] && [ -n "$SIBLING_PROJECT" ] && verify_key "$SIBLING_KEY"; then
    echo "ZERODB_API_KEY=${SIBLING_KEY}"
    echo "ZERODB_PROJECT_ID=${SIBLING_PROJECT}"
    exit 0
  fi
fi

# 4. Auto-provision a free trial project. Opt-out via ZERODB_NO_AUTO_PROVISION.
if [ "${ZERODB_NO_AUTO_PROVISION:-}" = "1" ]; then
  exit 1
fi

command -v curl >/dev/null 2>&1 || exit 1

# The SessionStart hook and the MCP server both invoke this script and can
# start within the same instant. Without a lock, both could provision a
# separate trial project. A flock-based lock makes the second caller wait
# for the first to finish and persist, then re-check the cache (case 2)
# instead of provisioning again.
LOCK_FILE="${CRED_DIR}.lock"
mkdir -p "$CRED_DIR"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -w 15 9; then
    exit 1
  fi
  # Someone else may have provisioned while we waited for the lock.
  if [ -f "$CRED_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CRED_FILE"
    if [ -n "${ZERODB_API_KEY:-}" ] && [ -n "${ZERODB_PROJECT_ID:-}" ] && verify_key "$ZERODB_API_KEY"; then
      echo "ZERODB_API_KEY=${ZERODB_API_KEY}"
      echo "ZERODB_PROJECT_ID=${ZERODB_PROJECT_ID}"
      exit 0
    fi
  fi
fi

SOURCE_LABEL="claude-code-plugin"
PROVISION_STATUS=$(curl -sS -o /tmp/zerodb-provision-resp.$$ -w '%{http_code}' -X POST "$PROVISION_URL" \
  -H "Content-Type: application/json" \
  -d "{\"source\": \"${SOURCE_LABEL}\", \"agree_terms\": true}" 2>/dev/null)
CURL_EXIT=$?
RESPONSE=$(cat /tmp/zerodb-provision-resp.$$ 2>/dev/null)
rm -f /tmp/zerodb-provision-resp.$$

if [ "$CURL_EXIT" -ne 0 ]; then
  echo "zerodb-memory: could not reach the ZeroDB trial provisioning endpoint (network error)." >&2
  exit 1
fi
if [ "$PROVISION_STATUS" = "429" ]; then
  echo "zerodb-memory: trial provisioning is rate-limited right now — try again in a minute, or set ZERODB_API_KEY to an existing key." >&2
  exit 1
fi
if [ "$PROVISION_STATUS" != "200" ] && [ "$PROVISION_STATUS" != "201" ]; then
  echo "zerodb-memory: trial provisioning failed (HTTP ${PROVISION_STATUS})." >&2
  exit 1
fi

PARSED=$(printf '%s' "$RESPONSE" | node -e '
  let d = "";
  process.stdin.on("data", c => d += c);
  process.stdin.on("end", () => {
    try {
      const j = JSON.parse(d);
      if (j.api_key && j.project_id) {
        process.stdout.write(j.api_key + "\n" + j.project_id + "\n" + (j.claim_url || ""));
      }
    } catch (e) { /* leave empty, caller checks */ }
  });
' 2>/dev/null) || exit 1

PROJECT_ID=$(printf '%s' "$PARSED" | sed -n '2p')
CLAIM_URL=$(printf '%s' "$PARSED" | sed -n '3p')
API_KEY=$(printf '%s' "$PARSED" | sed -n '1p')

if [ -z "$API_KEY" ] || [ -z "$PROJECT_ID" ]; then
  exit 1
fi

mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"
{
  echo "# Auto-provisioned by zerodb-memory Claude Code plugin on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# This is a free trial project. Claim it permanently at:"
  echo "#   ${CLAIM_URL}"
  echo "ZERODB_API_KEY=${API_KEY}"
  echo "ZERODB_PROJECT_ID=${PROJECT_ID}"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

# Surface the claim URL once, via the status cache the statusline/hooks read,
# so the user finds out their trial project exists and how to keep it.
CACHE_DIR="${TMPDIR:-/tmp}/zerodb-status"
mkdir -p "$CACHE_DIR"
echo "{\"count\": null, \"state\": \"trial_provisioned\", \"claim_url\": \"${CLAIM_URL}\", \"last_updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "${CACHE_DIR}/status.json"

echo "ZERODB_API_KEY=${API_KEY}"
echo "ZERODB_PROJECT_ID=${PROJECT_ID}"
