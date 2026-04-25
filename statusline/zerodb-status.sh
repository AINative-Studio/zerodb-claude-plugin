#!/usr/bin/env bash
# statusline/zerodb-status.sh — ZeroDB memory status bar widget
# Called periodically by Claude Code to update the status bar.
# Reads from a local cache file to avoid hitting the API on every poll.
# Refs #11

CACHE_DIR="${TMPDIR:-/tmp}/zerodb-status"
CACHE_FILE="${CACHE_DIR}/status.json"

# If no API key configured, show nothing (don't pollute status bar)
if [ -z "${ZERODB_API_KEY:-}" ]; then
  exit 0
fi

# Read from cache (written by hooks after each session operation)
if [ -f "$CACHE_FILE" ]; then
  COUNT=$(python3 -c "import json,sys; d=json.load(open('$CACHE_FILE')); print(d.get('count', '?'))" 2>/dev/null || echo "?")
  STATE=$(python3 -c "import json,sys; d=json.load(open('$CACHE_FILE')); print(d.get('state', 'synced'))" 2>/dev/null || echo "synced")

  case "$STATE" in
    saving)
      echo "ZeroDB: saving..."
      ;;
    synced)
      if [ "$COUNT" = "0" ] || [ "$COUNT" = "None" ]; then
        echo "ZeroDB: 0 memories"
      else
        echo "ZeroDB: $COUNT memories ✓"
      fi
      ;;
    error)
      echo "ZeroDB: offline"
      ;;
    *)
      echo "ZeroDB: $COUNT memories"
      ;;
  esac
else
  # No cache yet — first session, show ready state
  echo "ZeroDB: ready"
fi
