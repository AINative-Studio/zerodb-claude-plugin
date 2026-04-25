#!/usr/bin/env bash
# lib/project-id.sh — Shared project identity detection for ZeroDB plugin
# Source this file and call zerodb_get_project_id to get the normalized project ID.
# Refs #12
#
# Usage:
#   source "$(dirname "$0")/../lib/project-id.sh"
#   PROJECT=$(zerodb_get_project_id)

zerodb_get_project_id() {
  local remote=""
  local project=""

  # Must be in a git repo
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    # Fall back to directory name if not a git repo
    echo "local/$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    return
  fi

  # Try origin first, then any remote
  remote=$(git remote get-url origin 2>/dev/null || git remote get-url "$(git remote | head -1)" 2>/dev/null || echo "")

  if [ -z "$remote" ]; then
    # No remotes configured — use directory name
    echo "local/$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    return
  fi

  # Normalize various URL formats to org/repo:
  #
  # SSH formats:
  #   git@github.com:org/repo.git       -> org/repo
  #   git@gitlab.com:org/sub/repo.git   -> org/sub/repo
  #
  # HTTPS formats:
  #   https://github.com/org/repo.git   -> org/repo
  #   https://github.com/org/repo       -> org/repo
  #   https://user@github.com/org/repo  -> org/repo
  #
  # Supported hosts: github.com, gitlab.com, bitbucket.org, any custom host

  project=$(echo "$remote" \
    | sed 's|^git@[^:]*:||' \
    | sed -E 's|^https?://[^@]*@[^/]+/||' \
    | sed -E 's|^https?://[^/]+/||' \
    | sed 's|\.git$||' \
    | tr '[:upper:]' '[:lower:]')

  if [ -z "$project" ]; then
    echo "unknown/unknown"
    return
  fi

  echo "$project"
}

# Get just the repo name (last segment of org/repo)
zerodb_get_repo_name() {
  local project
  project=$(zerodb_get_project_id)
  echo "${project##*/}"
}

# Get just the org/owner (first segment of org/repo)
zerodb_get_org_name() {
  local project
  project=$(zerodb_get_project_id)
  echo "${project%%/*}"
}
