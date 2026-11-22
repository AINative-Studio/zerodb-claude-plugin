#!/usr/bin/env bash
# tests/test-team-project.sh — Test suite for lib/team-project.sh
# Refs #19
#
# Run from the repo root or from the tests/ directory:
#   bash tests/test-team-project.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    echo "  PASS: ${description}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${description}"
    echo "        expected: ${expected}"
    echo "        actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

assert_status() {
  local description="$1"
  local expected_status="$2"
  local actual_status="$3"

  if [ "$expected_status" = "$actual_status" ]; then
    echo "  PASS: ${description}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${description}"
    echo "        expected exit status: ${expected_status}"
    echo "        actual exit status:   ${actual_status}"
    FAIL=$((FAIL + 1))
  fi
}

# Create a fake repo directory, optionally with .claude/zerodb.json.
# $1 = "with-config" | "no-config" | "malformed-config" | "empty-team-id"
# $2 = teamProjectId (only used for "with-config")
# $3 = personalProjectId (optional, only used for "with-config")
make_fake_repo() {
  local mode="$1"
  local team_id="${2:-}"
  local personal_id="${3:-}"

  local repo_dir
  repo_dir="$(mktemp -d)"

  # A real git repo so `git rev-parse --show-toplevel` resolves to repo_dir
  # without needing a mocked git binary.
  git -C "$repo_dir" init -q

  case "$mode" in
    with-config)
      mkdir -p "${repo_dir}/.claude"
      if [ -n "$personal_id" ]; then
        cat > "${repo_dir}/.claude/zerodb.json" <<EOF
{
  "teamProjectId": "${team_id}",
  "personalProjectId": "${personal_id}"
}
EOF
      else
        cat > "${repo_dir}/.claude/zerodb.json" <<EOF
{
  "teamProjectId": "${team_id}"
}
EOF
      fi
      ;;
    malformed-config)
      mkdir -p "${repo_dir}/.claude"
      echo "{ this is not valid json" > "${repo_dir}/.claude/zerodb.json"
      ;;
    empty-team-id)
      mkdir -p "${repo_dir}/.claude"
      printf '{\n  "teamProjectId": ""\n}\n' > "${repo_dir}/.claude/zerodb.json"
      ;;
    no-config)
      : # no .claude/zerodb.json at all
      ;;
  esac

  echo "$repo_dir"
}

# ---------------------------------------------------------------------------
# Tests: zerodb_get_team_project_id
# ---------------------------------------------------------------------------

echo ""
echo "=== zerodb_get_team_project_id ==="
echo ""

repo_dir=$(make_fake_repo "with-config" "proj_team_abc123")
result=$(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_team_project_id)
rm -rf "$repo_dir"
assert_eq "reads teamProjectId from .claude/zerodb.json" "proj_team_abc123" "$result"

repo_dir=$(make_fake_repo "no-config")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_team_project_id >/dev/null 2>&1)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "exits non-zero when no config file exists" "1" "$status"

repo_dir=$(make_fake_repo "with-config" "proj_team_subdir")
subdir="${repo_dir}/src/nested"
mkdir -p "$subdir"
result=$(cd "$subdir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_team_project_id)
rm -rf "$repo_dir"
assert_eq "finds .claude/zerodb.json from a nested subdirectory via repo root" "proj_team_subdir" "$result"

repo_dir=$(make_fake_repo "malformed-config")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_team_project_id >/dev/null 2>&1)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "exits non-zero (not a crash) on malformed JSON" "1" "$status"

repo_dir=$(make_fake_repo "empty-team-id")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_team_project_id >/dev/null 2>&1)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "treats an empty-string teamProjectId as not configured" "1" "$status"

# ---------------------------------------------------------------------------
# Tests: zerodb_get_config_personal_project_id
# ---------------------------------------------------------------------------

echo ""
echo "=== zerodb_get_config_personal_project_id ==="
echo ""

repo_dir=$(make_fake_repo "with-config" "proj_team_1" "proj_personal_1")
result=$(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_config_personal_project_id)
rm -rf "$repo_dir"
assert_eq "reads personalProjectId when present" "proj_personal_1" "$result"

repo_dir=$(make_fake_repo "with-config" "proj_team_only")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_config_personal_project_id >/dev/null 2>&1)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "exits non-zero when personalProjectId absent from config" "1" "$status"

repo_dir=$(make_fake_repo "malformed-config")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_get_config_personal_project_id >/dev/null 2>&1)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "exits non-zero (not a crash) on malformed JSON" "1" "$status"

# ---------------------------------------------------------------------------
# Tests: zerodb_has_team_project
# ---------------------------------------------------------------------------

echo ""
echo "=== zerodb_has_team_project ==="
echo ""

repo_dir=$(make_fake_repo "with-config" "proj_team_present")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_has_team_project)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "returns success when a team project is configured" "0" "$status"

repo_dir=$(make_fake_repo "no-config")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_has_team_project)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "returns failure when no config file exists" "1" "$status"

repo_dir=$(make_fake_repo "malformed-config")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_has_team_project)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "returns failure (not a crash) on malformed JSON" "1" "$status"

repo_dir=$(make_fake_repo "empty-team-id")
set +e
(cd "$repo_dir" && source "${LIB_DIR}/team-project.sh" && zerodb_has_team_project)
status=$?
set -e
rm -rf "$repo_dir"
assert_status "returns failure for an empty-string teamProjectId" "1" "$status"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
