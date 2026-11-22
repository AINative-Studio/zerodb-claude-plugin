#!/usr/bin/env bash
# lib/team-project.sh — Shared team-project config for ZeroDB plugin
# Source this file and call zerodb_get_team_config to read the repo's
# .claude/zerodb.json, if one exists.
# Refs #19
#
# Usage:
#   source "$(dirname "$0")/../lib/team-project.sh"
#   TEAM_PROJECT_ID=$(zerodb_get_team_project_id)
#   PERSONAL_PROJECT_ID=$(zerodb_get_config_personal_project_id)

# Resolve .claude/zerodb.json relative to the git repo root, falling back
# to the current directory if not in a git repo (matches project-id.sh's
# own fallback behavior for consistency).
_zerodb_config_path() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="$(pwd)"
  echo "${repo_root}/.claude/zerodb.json"
}

# Extract a single string field from .claude/zerodb.json without requiring
# a JSON parser to be installed -- the file is small and flat, so a
# targeted grep/sed is sufficient and matches this plugin's existing
# dependency-free shell style (see lib/ensure-credentials.sh).
_zerodb_config_field() {
  local field="$1"
  local config_file
  config_file=$(_zerodb_config_path)

  [ -f "$config_file" ] || return 1

  local value
  value=$(grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$config_file" 2>/dev/null \
    | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')

  [ -n "$value" ] || return 1
  echo "$value"
}

# Returns the team ZeroDB project ID from .claude/zerodb.json, or nothing
# (exit 1) if no team project is configured for this repo.
zerodb_get_team_project_id() {
  _zerodb_config_field "teamProjectId"
}

# Returns the personal ZeroDB project ID override from .claude/zerodb.json,
# if the repo's config specifies one. Most installs won't set this --
# the personal project normally comes from ensure-credentials.sh's normal
# resolution (env var, persisted cache, or auto-provisioned trial) instead.
zerodb_get_config_personal_project_id() {
  _zerodb_config_field "personalProjectId"
}

# True (exit 0) if this repo has a team project configured at all.
zerodb_has_team_project() {
  zerodb_get_team_project_id >/dev/null 2>&1
}
