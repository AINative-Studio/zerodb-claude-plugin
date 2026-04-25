#!/usr/bin/env bash
# tests/test-project-id.sh — Test suite for lib/project-id.sh
# Refs #12
#
# Run from the repo root or from the tests/ directory:
#   bash tests/test-project-id.sh

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

# Create a temporary directory containing a 'git' mock script.
# Caller must rm -rf the returned path when done.
#
# $1 = mock mode: "no-git" | "no-remote" | "has-remote"
# $2 = remote URL (only used when mode is "has-remote")
make_mock_git_dir() {
  local mode="$1"
  local remote_url="${2:-}"

  local mock_dir
  mock_dir="$(mktemp -d)"
  local mock_git="${mock_dir}/git"

  case "$mode" in
    no-git)
      # git rev-parse --git-dir returns non-zero → not a git repo
      cat > "$mock_git" <<'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
      ;;
    no-remote)
      cat > "$mock_git" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$*" == *"rev-parse"* ]]; then
  echo ".git"
  exit 0
fi
# remote get-url → fail (no remotes)
exit 1
MOCKEOF
      ;;
    has-remote)
      cat > "$mock_git" <<MOCKEOF
#!/usr/bin/env bash
if [[ "\$*" == *"rev-parse"* ]]; then
  echo ".git"
  exit 0
fi
if [[ "\$*" == *"remote get-url"* ]]; then
  echo "${remote_url}"
  exit 0
fi
if [[ "\$*" == *"remote"* ]]; then
  echo "origin"
  exit 0
fi
exit 1
MOCKEOF
      ;;
  esac

  chmod +x "$mock_git"
  echo "$mock_dir"
}

# Run zerodb_get_project_id with a mocked git environment.
# $1 = mock mode: "no-git" | "no-remote" | "has-remote"
# $2 = remote URL (only used when mode is "has-remote")
# $3 = working directory leaf name (optional; a temp dir is created)
run_with_mock() {
  local mode="$1"
  local remote_url="${2:-}"
  local leaf_dir="${3:-}"

  local mock_dir
  mock_dir="$(make_mock_git_dir "$mode" "$remote_url")"

  local work_base
  work_base="$(mktemp -d)"
  local work_dir
  if [ -n "$leaf_dir" ]; then
    work_dir="${work_base}/${leaf_dir}"
    mkdir -p "$work_dir"
  else
    work_dir="$work_base"
  fi

  local result
  result=$(PATH="${mock_dir}:${PATH}" bash -c "
    cd '${work_dir}'
    source '${LIB_DIR}/project-id.sh'
    zerodb_get_project_id
  ")

  rm -rf "$mock_dir" "$work_base"
  echo "$result"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo ""
echo "=== zerodb_get_project_id ==="
echo ""

# 1. SSH github.com
result=$(run_with_mock "has-remote" "git@github.com:myorg/myrepo.git")
assert_eq "SSH github.com: git@github.com:myorg/myrepo.git" "myorg/myrepo" "$result"

# 2. HTTPS github.com with .git suffix
result=$(run_with_mock "has-remote" "https://github.com/myorg/myrepo.git")
assert_eq "HTTPS github.com with .git" "myorg/myrepo" "$result"

# 3. HTTPS github.com without .git suffix
result=$(run_with_mock "has-remote" "https://github.com/myorg/myrepo")
assert_eq "HTTPS github.com without .git" "myorg/myrepo" "$result"

# 4. HTTPS with embedded credentials
result=$(run_with_mock "has-remote" "https://user:token@github.com/myorg/myrepo.git")
assert_eq "HTTPS with credentials" "myorg/myrepo" "$result"

# 5. SSH gitlab.com
result=$(run_with_mock "has-remote" "git@gitlab.com:myorg/myrepo.git")
assert_eq "SSH gitlab.com" "myorg/myrepo" "$result"

# 6. SSH gitlab.com with subgroups
result=$(run_with_mock "has-remote" "git@gitlab.com:myorg/subgroup/myrepo.git")
assert_eq "SSH gitlab.com with subgroup" "myorg/subgroup/myrepo" "$result"

# 7. SSH bitbucket.org
result=$(run_with_mock "has-remote" "git@bitbucket.org:myorg/myrepo.git")
assert_eq "SSH bitbucket.org" "myorg/myrepo" "$result"

# 8. HTTPS uppercase (should be lowercased)
result=$(run_with_mock "has-remote" "https://github.com/MyOrg/MyRepo.git")
assert_eq "HTTPS uppercase normalised to lowercase" "myorg/myrepo" "$result"

# 9. No remote configured — fallback to dir name
result=$(run_with_mock "no-remote" "" "my-project")
assert_eq "No remote: fallback to local/dir-name" "local/my-project" "$result"

# 10. Not a git repo — fallback to dir name
result=$(run_with_mock "no-git" "" "cool-app")
assert_eq "Not a git repo: fallback to local/dir-name" "local/cool-app" "$result"

echo ""
echo "=== zerodb_get_repo_name ==="
echo ""

mock_dir="$(make_mock_git_dir "has-remote" "git@github.com:acme/widget.git")"
result=$(PATH="${mock_dir}:${PATH}" bash -c "
  source '${LIB_DIR}/project-id.sh'
  zerodb_get_repo_name
")
rm -rf "$mock_dir"
assert_eq "zerodb_get_repo_name returns repo segment" "widget" "$result"

echo ""
echo "=== zerodb_get_org_name ==="
echo ""

mock_dir="$(make_mock_git_dir "has-remote" "git@github.com:acme/widget.git")"
result=$(PATH="${mock_dir}:${PATH}" bash -c "
  source '${LIB_DIR}/project-id.sh'
  zerodb_get_org_name
")
rm -rf "$mock_dir"
assert_eq "zerodb_get_org_name returns org segment" "acme" "$result"

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
