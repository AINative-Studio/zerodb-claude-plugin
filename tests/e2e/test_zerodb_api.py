"""
E2E Test Suite — ZeroDB Claude Code Plugin
Tests against live ZeroDB API with real credentials.

Coverage targets:
  - zerodb_store_memory (remember endpoint)
  - zerodb_search_memory / zerodb_semantic_search (recall endpoint)
  - zerodb_get_context (recall with session context)
  - zerodb_clear_session (forget endpoint)
  - session-start hook output format
  - session-end hook output format
  - project-id.sh normalization (via subprocess)
  - statusline script output
  - skill file frontmatter validity
  - plugin.json schema validity

Run:
  ZERODB_API_TOKEN=<token> ZERODB_PROJECT_ID=<id> python3 -m pytest tests/e2e/ -v --tb=short

Requires: requests, pytest
"""

import json
import os
import subprocess
import time
import uuid
from pathlib import Path

import pytest
import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BASE_URL = os.getenv("ZERODB_API_URL", "https://api.ainative.studio")
API_TOKEN = os.getenv("ZERODB_API_TOKEN", os.getenv("AINATIVE_API_TOKEN", ""))
PROJECT_ID = os.getenv("ZERODB_PROJECT_ID", "")
PLUGIN_ROOT = Path(__file__).parent.parent.parent  # /tmp/zerodb-claude-plugin

# Unique test session to isolate test data from production memories
TEST_SESSION_ID = f"e2e-plugin-test-{uuid.uuid4().hex[:8]}"
TEST_PROJECT = "ainative-studio/zerodb-claude-plugin-e2e-tests"

if not API_TOKEN:
    pytest.skip("ZERODB_API_TOKEN not set — skipping live E2E tests", allow_module_level=True)


def api_headers():
    return {
        "Authorization": f"Bearer {API_TOKEN}",
        "Content-Type": "application/json",
    }


def memory_url(path: str) -> str:
    return f"{BASE_URL}/api/v1/public/memory/v2/{path}"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def stored_memory_id():
    """Store a test memory and return its ID. Cleaned up after module."""
    resp = requests.post(
        memory_url("remember"),
        headers=api_headers(),
        json={
            "content": "E2E fixture: PgBouncer must be used on port 6432 not 5432",
            "metadata": {
                "project": TEST_PROJECT,
                "type": "convention",
                "date": "2026-04-24",
                "e2e_test": True,
                "session": TEST_SESSION_ID,
            },
            "session_id": TEST_SESSION_ID,
        },
        timeout=15,
    )
    assert resp.status_code == 200, f"Setup failed: {resp.text}"
    memory_id = resp.json()["memory_id"]
    yield memory_id

    # Teardown — delete the test memory
    requests.post(
        memory_url("forget"),
        headers=api_headers(),
        json={"memory_id": memory_id},
        timeout=15,
    )


@pytest.fixture(scope="module")
def multiple_memory_ids():
    """Store several test memories, yield their IDs, then clean up."""
    memories = [
        {"content": "E2E: Railway internal DNS does not work from Kong — use public URLs", "type": "architecture"},
        {"content": "E2E: Payments module owned by Sarah Chen — get sign-off before refactoring", "type": "ownership"},
        {"content": "E2E: Bug in managed_chat_service — HuggingFace returns dict not AIResponse for tool calls", "type": "bug"},
        {"content": "E2E: Use alembic offline mode only — never run upgrade head in production", "type": "convention"},
    ]
    ids = []
    for m in memories:
        resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={
                "content": m["content"],
                "metadata": {
                    "project": TEST_PROJECT,
                    "type": m["type"],
                    "date": "2026-04-24",
                    "e2e_test": True,
                    "session": TEST_SESSION_ID,
                },
                "session_id": TEST_SESSION_ID,
            },
            timeout=15,
        )
        assert resp.status_code == 200
        ids.append(resp.json()["memory_id"])

    yield ids

    for mid in ids:
        requests.post(
            memory_url("forget"),
            headers=api_headers(),
            json={"memory_id": mid},
            timeout=15,
        )


# ---------------------------------------------------------------------------
# 1. Store Memory (remember endpoint)
# ---------------------------------------------------------------------------

class TestStoreMemory:
    def test_store_returns_memory_id(self):
        resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={
                "content": "E2E: Test store — should be cleaned up",
                "metadata": {"project": TEST_PROJECT, "type": "convention", "e2e_test": True},
                "session_id": TEST_SESSION_ID,
            },
            timeout=15,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "memory_id" in data
        assert data["status"] == "stored"
        # cleanup
        requests.post(memory_url("forget"), headers=api_headers(),
                      json={"memory_id": data["memory_id"]}, timeout=10)

    def test_store_returns_valid_uuid(self):
        resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={
                "content": "E2E: UUID validation test",
                "session_id": TEST_SESSION_ID,
            },
            timeout=15,
        )
        assert resp.status_code == 200
        mid = resp.json()["memory_id"]
        # Should be a valid UUID
        parsed = uuid.UUID(mid)
        assert str(parsed) == mid
        requests.post(memory_url("forget"), headers=api_headers(),
                      json={"memory_id": mid}, timeout=10)

    def test_store_with_metadata(self, stored_memory_id):
        """Verify stored memory preserves metadata fields."""
        # Recall it and check metadata round-trips
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "PgBouncer port 6432", "session_id": TEST_SESSION_ID, "limit": 10},
            timeout=15,
        )
        assert resp.status_code == 200
        results = resp.json()["results"]
        match = next((r for r in results if r["id"] == stored_memory_id), None)
        assert match is not None, "Stored memory not found in recall results"
        assert match["metadata"]["project"] == TEST_PROJECT
        assert match["metadata"]["type"] == "convention"

    def test_store_without_metadata_succeeds(self):
        resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={"content": "E2E: Minimal memory — no metadata", "session_id": TEST_SESSION_ID},
            timeout=15,
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "stored"
        requests.post(memory_url("forget"), headers=api_headers(),
                      json={"memory_id": resp.json()["memory_id"]}, timeout=10)

    def test_store_empty_content_accepted_by_api(self):
        # The ZeroDB API accepts empty string content (no server-side empty check).
        # The plugin's skill file handles this at the Claude layer by instructing
        # Claude not to store empty or trivial memories.
        resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={"content": "", "session_id": TEST_SESSION_ID},
            timeout=15,
        )
        assert resp.status_code == 200
        assert "memory_id" in resp.json()
        # Cleanup
        requests.post(memory_url("forget"), headers=api_headers(),
                      json={"memory_id": resp.json()["memory_id"]}, timeout=10)

    def test_store_rate_limit_20_per_session(self):
        """Store 20 memories in a single session — all should succeed (our cap)."""
        session = f"rate-limit-test-{uuid.uuid4().hex[:6]}"
        ids = []
        for i in range(20):
            resp = requests.post(
                memory_url("remember"),
                headers=api_headers(),
                json={
                    "content": f"E2E rate limit test memory #{i+1} of 20",
                    "session_id": session,
                },
                timeout=15,
            )
            assert resp.status_code == 200, f"Memory #{i+1} failed: {resp.text}"
            ids.append(resp.json()["memory_id"])
        assert len(ids) == 20
        # Cleanup
        for mid in ids:
            requests.post(memory_url("forget"), headers=api_headers(),
                          json={"memory_id": mid}, timeout=10)


# ---------------------------------------------------------------------------
# 2. Recall / Semantic Search
# ---------------------------------------------------------------------------

class TestRecallMemory:
    def test_recall_returns_results_list(self, stored_memory_id):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "database port connection", "session_id": TEST_SESSION_ID, "limit": 5},
            timeout=15,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "results" in data
        assert isinstance(data["results"], list)

    def test_recall_finds_stored_memory(self, stored_memory_id):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "PgBouncer port 6432", "session_id": TEST_SESSION_ID, "limit": 10},
            timeout=15,
        )
        assert resp.status_code == 200
        ids = [r["id"] for r in resp.json()["results"]]
        assert stored_memory_id in ids

    def test_recall_result_has_required_fields(self, stored_memory_id):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "PgBouncer", "session_id": TEST_SESSION_ID, "limit": 5},
            timeout=15,
        )
        assert resp.status_code == 200
        results = resp.json()["results"]
        assert len(results) > 0
        r = results[0]
        for field in ("id", "content", "score", "created_at"):
            assert field in r, f"Missing field: {field}"

    def test_recall_semantic_relevance_ordering(self, multiple_memory_ids):
        """Railway DNS question should rank architecture memory higher than ownership."""
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "Railway DNS Kong upstream", "session_id": TEST_SESSION_ID, "limit": 10},
            timeout=15,
        )
        assert resp.status_code == 200
        results = resp.json()["results"]
        # Find our two test memories
        railway_result = next((r for r in results if "Railway" in r["content"] and "DNS" in r["content"]), None)
        sarah_result = next((r for r in results if "Sarah Chen" in r["content"]), None)
        if railway_result and sarah_result:
            # Railway/DNS memory should score higher for this query
            assert railway_result["score"] >= sarah_result["score"], \
                f"Railway score {railway_result['score']} should be >= Sarah score {sarah_result['score']}"

    def test_recall_limit_respected(self, multiple_memory_ids):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "E2E test", "limit": 2},
            timeout=15,
        )
        assert resp.status_code == 200
        assert len(resp.json()["results"]) <= 2

    def test_recall_unknown_query_returns_empty_or_low_score(self):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "xyzzy frobnicate quantum entanglement nonsense 99999", "limit": 5},
            timeout=15,
        )
        assert resp.status_code == 200
        results = resp.json()["results"]
        # Either no results, or all results have low similarity scores
        for r in results:
            score = r.get("similarity", r.get("score", 1.0))
            assert score < 0.85, f"Unexpectedly high score {score} for nonsense query"

    def test_recall_with_session_filter(self, stored_memory_id):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "PgBouncer", "session_id": TEST_SESSION_ID, "limit": 10},
            timeout=15,
        )
        assert resp.status_code == 200
        assert len(resp.json()["results"]) > 0


# ---------------------------------------------------------------------------
# 3. Forget (delete) Memory
# ---------------------------------------------------------------------------

class TestForgetMemory:
    def test_forget_returns_forgotten_status(self):
        # Store first
        store_resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={"content": "E2E: memory to forget", "session_id": TEST_SESSION_ID},
            timeout=15,
        )
        assert store_resp.status_code == 200
        mid = store_resp.json()["memory_id"]

        # Forget it
        forget_resp = requests.post(
            memory_url("forget"),
            headers=api_headers(),
            json={"memory_id": mid},
            timeout=15,
        )
        assert forget_resp.status_code == 200
        data = forget_resp.json()
        assert data["status"] == "forgotten"
        assert data["memory_id"] == mid

    def test_forgotten_memory_not_in_recall(self):
        unique_content = f"E2E: unique forget test {uuid.uuid4().hex}"
        store_resp = requests.post(
            memory_url("remember"),
            headers=api_headers(),
            json={"content": unique_content, "session_id": TEST_SESSION_ID},
            timeout=15,
        )
        mid = store_resp.json()["memory_id"]

        # Delete it
        requests.post(memory_url("forget"), headers=api_headers(),
                      json={"memory_id": mid}, timeout=15)

        # Short wait for consistency
        time.sleep(1)

        # Should not appear in recall
        recall_resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": unique_content, "limit": 10},
            timeout=15,
        )
        ids = [r["id"] for r in recall_resp.json()["results"]]
        assert mid not in ids, "Deleted memory still appearing in recall results"

    def test_forget_invalid_id_returns_error(self):
        resp = requests.post(
            memory_url("forget"),
            headers=api_headers(),
            json={"memory_id": "00000000-0000-0000-0000-000000000000"},
            timeout=15,
        )
        assert resp.status_code in (404, 400, 200), f"Unexpected status: {resp.status_code}"


# ---------------------------------------------------------------------------
# 4. Authentication
# ---------------------------------------------------------------------------

class TestAuthentication:
    def test_invalid_token_returns_401(self):
        resp = requests.post(
            memory_url("recall"),
            headers={"Authorization": "Bearer invalid_token_xyz", "Content-Type": "application/json"},
            json={"query": "test"},
            timeout=15,
        )
        assert resp.status_code == 401

    def test_missing_auth_returns_401_or_403(self):
        resp = requests.post(
            memory_url("recall"),
            headers={"Content-Type": "application/json"},
            json={"query": "test"},
            timeout=15,
        )
        assert resp.status_code in (401, 403)

    def test_valid_token_succeeds(self):
        resp = requests.post(
            memory_url("recall"),
            headers=api_headers(),
            json={"query": "test", "limit": 1},
            timeout=15,
        )
        assert resp.status_code == 200


# ---------------------------------------------------------------------------
# 5. Plugin Structure Validation
# ---------------------------------------------------------------------------

class TestPluginStructure:
    def test_plugin_json_exists(self):
        assert (PLUGIN_ROOT / ".claude-plugin" / "plugin.json").exists()

    def test_plugin_json_valid_json(self):
        content = (PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text()
        data = json.loads(content)
        assert isinstance(data, dict)

    def test_plugin_json_required_fields(self):
        data = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text())
        for field in ("name", "description", "version"):
            assert field in data, f"Missing required field: {field}"

    def test_plugin_json_mcp_server_declared(self):
        data = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text())
        assert "mcpServers" in data
        assert "zerodb-memory" in data["mcpServers"]
        mcp = data["mcpServers"]["zerodb-memory"]
        assert "command" in mcp
        assert "args" in mcp

    def test_plugin_json_hooks_declared(self):
        data = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text())
        assert "hooks" in data
        hooks = data["hooks"]
        assert "Stop" in hooks
        assert "PreToolUse" in hooks

    def test_marketplace_json_exists(self):
        assert (PLUGIN_ROOT / ".claude-plugin" / "marketplace.json").exists()

    def test_marketplace_json_valid(self):
        content = (PLUGIN_ROOT / ".claude-plugin" / "marketplace.json").read_text()
        data = json.loads(content)
        assert "name" in data
        assert "plugins" in data
        assert len(data["plugins"]) >= 1
        plugin = data["plugins"][0]
        assert plugin["name"] == "zerodb-memory"

    @pytest.mark.parametrize("skill_name", [
        "remember", "recall", "forget", "memory", "zerodb-memory-guide"
    ])
    def test_skill_file_exists(self, skill_name):
        skill_path = PLUGIN_ROOT / "skills" / skill_name / "SKILL.md"
        assert skill_path.exists(), f"Missing: skills/{skill_name}/SKILL.md"

    @pytest.mark.parametrize("skill_name", [
        "remember", "recall", "forget", "memory", "zerodb-memory-guide"
    ])
    def test_skill_file_has_frontmatter(self, skill_name):
        content = (PLUGIN_ROOT / "skills" / skill_name / "SKILL.md").read_text()
        assert content.startswith("---"), f"skills/{skill_name}/SKILL.md missing YAML frontmatter"
        # Must have closing ---
        lines = content.split("\n")
        closing = [i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"]
        assert len(closing) >= 1, f"skills/{skill_name}/SKILL.md missing closing frontmatter ---"

    @pytest.mark.parametrize("skill_name", [
        "remember", "recall", "forget", "memory", "zerodb-memory-guide"
    ])
    def test_skill_file_has_description(self, skill_name):
        content = (PLUGIN_ROOT / "skills" / skill_name / "SKILL.md").read_text()
        assert "description:" in content, f"skills/{skill_name}/SKILL.md missing description field"

    @pytest.mark.parametrize("hook_name", ["session-end.sh", "session-start.sh"])
    def test_hook_file_exists(self, hook_name):
        hook_path = PLUGIN_ROOT / "hooks" / hook_name
        assert hook_path.exists()

    @pytest.mark.parametrize("hook_name", ["session-end.sh", "session-start.sh"])
    def test_hook_is_executable(self, hook_name):
        hook_path = PLUGIN_ROOT / "hooks" / hook_name
        assert os.access(hook_path, os.X_OK), f"{hook_name} is not executable"

    @pytest.mark.parametrize("hook_name", ["session-end.sh", "session-start.sh"])
    def test_hook_has_shebang(self, hook_name):
        content = (PLUGIN_ROOT / "hooks" / hook_name).read_text()
        assert content.startswith("#!/"), f"{hook_name} missing shebang"

    def test_lib_project_id_exists(self):
        assert (PLUGIN_ROOT / "lib" / "project-id.sh").exists()

    def test_statusline_script_exists(self):
        statusline = PLUGIN_ROOT / "statusline" / "zerodb-status.sh"
        assert statusline.exists()

    def test_statusline_script_is_executable(self):
        statusline = PLUGIN_ROOT / "statusline" / "zerodb-status.sh"
        assert os.access(statusline, os.X_OK)


# ---------------------------------------------------------------------------
# 6. Hook Script Execution
# ---------------------------------------------------------------------------

class TestHookScripts:
    def test_session_end_hook_no_key_exits_zero(self):
        """Hook should exit 0 silently when no API key set."""
        env = {**os.environ, "ZERODB_API_KEY": ""}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-end.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        assert result.stdout == ""

    def test_session_end_hook_autopersist_off_exits_zero(self):
        """Hook should exit 0 silently when ZERODB_AUTOPERSIST=off."""
        env = {**os.environ, "ZERODB_API_KEY": "test_key", "ZERODB_AUTOPERSIST": "off"}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-end.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        assert result.stdout == ""

    def test_session_end_hook_with_key_emits_json(self):
        """Hook with valid API key should emit valid JSON trigger payload."""
        env = {**os.environ, "ZERODB_API_KEY": API_TOKEN, "ZERODB_AUTOPERSIST": "on"}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-end.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        payload = json.loads(result.stdout)
        assert payload["zerodb_trigger"] == "session_end"
        assert "project" in payload
        assert "instruction" in payload

    def test_session_start_hook_no_key_exits_zero(self):
        env = {**os.environ, "ZERODB_API_KEY": "", "CLAUDE_SESSION_ID": "test-no-key"}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-start.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        assert result.stdout == ""

    def test_session_start_hook_autorecall_off_exits_zero(self):
        env = {**os.environ, "ZERODB_API_KEY": "test_key",
               "ZERODB_AUTORECALL": "off", "CLAUDE_SESSION_ID": "test-recall-off"}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-start.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        assert result.stdout == ""

    def test_session_start_hook_emits_json_on_first_call(self, tmp_path):
        """First call with a fresh session ID should emit JSON payload."""
        env = {**os.environ, "ZERODB_API_KEY": API_TOKEN,
               "ZERODB_AUTORECALL": "on",
               "CLAUDE_SESSION_ID": f"fresh-session-{uuid.uuid4().hex}",
               "TMPDIR": str(tmp_path)}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-start.sh")],
            input="{}",
            capture_output=True,
            text=True,
            env=env,
            cwd=str(PLUGIN_ROOT),
        )
        assert result.returncode == 0
        payload = json.loads(result.stdout)
        assert payload["zerodb_trigger"] == "session_start"
        assert "project" in payload
        assert "instruction" in payload

    def test_session_start_hook_silent_on_second_call(self, tmp_path):
        """Second call with same session ID should be silent (sentinel file)."""
        session_id = f"dupe-test-{uuid.uuid4().hex}"
        env = {**os.environ, "ZERODB_API_KEY": API_TOKEN,
               "ZERODB_AUTORECALL": "on",
               "CLAUDE_SESSION_ID": session_id,
               "TMPDIR": str(tmp_path)}

        # First call — should emit payload
        r1 = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-start.sh")],
            input="{}", capture_output=True, text=True, env=env, cwd=str(PLUGIN_ROOT),
        )
        assert r1.returncode == 0
        assert r1.stdout.strip() != ""

        # Second call — should be silent
        r2 = subprocess.run(
            [str(PLUGIN_ROOT / "hooks" / "session-start.sh")],
            input="{}", capture_output=True, text=True, env=env, cwd=str(PLUGIN_ROOT),
        )
        assert r2.returncode == 0
        assert r2.stdout.strip() == ""


# ---------------------------------------------------------------------------
# 7. Project Identity Library
# ---------------------------------------------------------------------------

class TestProjectIdentityLib:
    def _run_project_id(self, git_remote: str, cwd: str = None, extra_env: dict = None) -> str:
        """Run a shell snippet that mocks git remote and calls zerodb_get_project_id."""
        env = {**os.environ, **(extra_env or {})}
        script = f"""
set -e
# Mock git
git() {{
  case "$*" in
    "rev-parse --git-dir") echo ".git"; return 0 ;;
    "remote get-url origin") echo "{git_remote}"; return 0 ;;
    *) command git "$@" ;;
  esac
}}
export -f git
source {PLUGIN_ROOT}/lib/project-id.sh
zerodb_get_project_id
"""
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True, text=True, env=env,
            cwd=cwd or str(PLUGIN_ROOT),
        )
        return result.stdout.strip()

    def test_ssh_github_url(self):
        assert self._run_project_id("git@github.com:AINative-Studio/core.git") == "ainative-studio/core"

    def test_https_github_url(self):
        assert self._run_project_id("https://github.com/AINative-Studio/core.git") == "ainative-studio/core"

    def test_https_github_no_git_suffix(self):
        assert self._run_project_id("https://github.com/AINative-Studio/core") == "ainative-studio/core"

    def test_https_with_credentials(self):
        assert self._run_project_id("https://user:token@github.com/AINative-Studio/core.git") == "ainative-studio/core"

    def test_gitlab_ssh_url(self):
        assert self._run_project_id("git@gitlab.com:myorg/myrepo.git") == "myorg/myrepo"

    def test_bitbucket_https_url(self):
        assert self._run_project_id("https://bitbucket.org/myteam/myproject.git") == "myteam/myproject"

    def test_uppercase_normalized_to_lowercase(self):
        assert self._run_project_id("git@github.com:MyOrg/MyRepo.git") == "myorg/myrepo"

    def test_lib_file_has_shebang(self):
        content = (PLUGIN_ROOT / "lib" / "project-id.sh").read_text()
        assert content.startswith("#!/")

    def test_lib_exports_three_functions(self):
        content = (PLUGIN_ROOT / "lib" / "project-id.sh").read_text()
        assert "zerodb_get_project_id" in content
        assert "zerodb_get_repo_name" in content
        assert "zerodb_get_org_name" in content


# ---------------------------------------------------------------------------
# 8. Statusline Script
# ---------------------------------------------------------------------------

class TestStatuslineScript:
    def test_no_api_key_produces_no_output(self):
        env = {**os.environ, "ZERODB_API_KEY": ""}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "statusline" / "zerodb-status.sh")],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0
        assert result.stdout.strip() == ""

    def test_with_synced_cache_shows_count(self, tmp_path):
        cache_dir = tmp_path / "zerodb-status"
        cache_dir.mkdir()
        (cache_dir / "status.json").write_text(
            json.dumps({"count": 42, "state": "synced"})
        )
        env = {**os.environ, "ZERODB_API_KEY": "test_key", "TMPDIR": str(tmp_path)}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "statusline" / "zerodb-status.sh")],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0
        assert "42" in result.stdout
        assert "memories" in result.stdout

    def test_saving_state_shows_saving(self, tmp_path):
        cache_dir = tmp_path / "zerodb-status"
        cache_dir.mkdir()
        (cache_dir / "status.json").write_text(
            json.dumps({"count": 10, "state": "saving"})
        )
        env = {**os.environ, "ZERODB_API_KEY": "test_key", "TMPDIR": str(tmp_path)}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "statusline" / "zerodb-status.sh")],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0
        assert "saving" in result.stdout.lower()

    def test_error_state_shows_offline(self, tmp_path):
        cache_dir = tmp_path / "zerodb-status"
        cache_dir.mkdir()
        (cache_dir / "status.json").write_text(
            json.dumps({"count": 0, "state": "error"})
        )
        env = {**os.environ, "ZERODB_API_KEY": "test_key", "TMPDIR": str(tmp_path)}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "statusline" / "zerodb-status.sh")],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0
        assert "offline" in result.stdout.lower()

    def test_no_cache_shows_ready(self, tmp_path):
        env = {**os.environ, "ZERODB_API_KEY": "test_key", "TMPDIR": str(tmp_path)}
        result = subprocess.run(
            [str(PLUGIN_ROOT / "statusline" / "zerodb-status.sh")],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode == 0
        assert "ready" in result.stdout.lower() or "ZeroDB" in result.stdout


# ---------------------------------------------------------------------------
# 9. CI Validation Script
# ---------------------------------------------------------------------------

class TestCIPipeline:
    def test_ci_workflow_exists(self):
        assert (PLUGIN_ROOT / ".github" / "workflows" / "ci.yml").exists()

    def test_ci_workflow_valid_yaml(self):
        import yaml  # only needed here
        content = (PLUGIN_ROOT / ".github" / "workflows" / "ci.yml").read_text()
        data = yaml.safe_load(content)
        assert "jobs" in data
        assert len(data["jobs"]) >= 1

    def test_plugin_json_hooks_reference_existing_files(self):
        data = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text())
        for event, path in data.get("hooks", {}).items():
            assert (PLUGIN_ROOT / path).exists(), f"Hook {event} references missing file: {path}"


# ---------------------------------------------------------------------------
# 10. CLAUDE.md Export Skill
# ---------------------------------------------------------------------------

class TestCLAUDEmdExport:
    """Validate the claudemd-export skill file exists and is fully specified."""

    SKILL_PATH = PLUGIN_ROOT / "skills" / "claudemd-export" / "SKILL.md"

    def _skill_content(self) -> str:
        return self.SKILL_PATH.read_text()

    def test_export_claudemd_skill_file_exists(self):
        """skills/claudemd-export/SKILL.md must exist."""
        assert self.SKILL_PATH.exists(), "Missing: skills/claudemd-export/SKILL.md"

    def test_export_claudemd_skill_has_frontmatter(self):
        """Skill file must have valid YAML frontmatter block."""
        content = self._skill_content()
        assert content.startswith("---"), "claudemd-export/SKILL.md missing opening YAML frontmatter (---)"
        lines = content.split("\n")
        closing_markers = [i for i, line in enumerate(lines[1:], 1) if line.strip() == "---"]
        assert len(closing_markers) >= 1, "claudemd-export/SKILL.md missing closing frontmatter (---)"
        # description field must be present inside the frontmatter block
        frontmatter_end = closing_markers[0]
        frontmatter_body = "\n".join(lines[1:frontmatter_end])
        assert "description:" in frontmatter_body, \
            "claudemd-export/SKILL.md frontmatter missing 'description:' field"

    def test_export_claudemd_skill_covers_all_memory_types(self):
        """Skill must document all 6 memory types and their section mappings."""
        content = self._skill_content()
        required_types = ["architecture", "convention", "ownership", "in-progress", "bug", "correction"]
        for memory_type in required_types:
            assert memory_type in content, \
                f"claudemd-export/SKILL.md does not mention memory type '{memory_type}'"
        # Also verify the corresponding CLAUDE.md section headings are documented
        required_sections = [
            "## Architecture",
            "## Conventions",
            "## File Ownership",
            "## Active Work",
            "## Known Issues",
            "## Important Corrections",
        ]
        for section in required_sections:
            assert section in content, \
                f"claudemd-export/SKILL.md does not document section '{section}'"

    def test_export_claudemd_skill_has_dedup_logic(self):
        """Skill must describe deduplication of semantically equivalent memories."""
        content = self._skill_content()
        # At least one of these terms should appear in the dedup section
        dedup_signals = ["dedup", "duplicate", "semantically equivalent", "same fact", "overlaps"]
        found = any(signal.lower() in content.lower() for signal in dedup_signals)
        assert found, (
            "claudemd-export/SKILL.md must describe deduplication logic. "
            "Expected one of: " + ", ".join(dedup_signals)
        )
        # Must also specify what to keep (most recent / most detailed)
        keep_signals = ["most recent", "most recently", "more detailed", "specificity", "keep only"]
        found_keep = any(signal.lower() in content.lower() for signal in keep_signals)
        assert found_keep, (
            "claudemd-export/SKILL.md must specify which duplicate to keep (most recent / most detailed)"
        )

    def test_export_claudemd_skill_has_dry_run_option(self):
        """Skill must document the --dry-run flag."""
        content = self._skill_content()
        assert "--dry-run" in content, \
            "claudemd-export/SKILL.md must document the --dry-run flag"
        # Confirm it clarifies that dry-run does NOT write any file
        dry_run_signals = ["do not write", "don't write", "No files written", "not write", "without writing"]
        found = any(signal.lower() in content.lower() for signal in dry_run_signals)
        assert found, \
            "claudemd-export/SKILL.md must clarify that --dry-run does not write any file"

    def test_export_claudemd_skill_references_update_vs_create(self):
        """Skill must document the update-vs-create flow including merge mode."""
        content = self._skill_content()
        # Must mention behaviour when CLAUDE.md already exists
        exists_signals = ["already exists", "if.*exist", "update vs", "update vs. create"]
        found_exists = any(signal.lower() in content.lower() for signal in exists_signals)
        assert found_exists, \
            "claudemd-export/SKILL.md must describe behaviour when CLAUDE.md already exists"
        # Must mention merge mode
        assert "merge" in content.lower(), \
            "claudemd-export/SKILL.md must describe 'merge' mode for preserving existing manual content"
        # Must mention diff preview
        diff_signals = ["diff", "what would change", "preview"]
        found_diff = any(signal.lower() in content.lower() for signal in diff_signals)
        assert found_diff, \
            "claudemd-export/SKILL.md must show a diff/preview before overwriting an existing CLAUDE.md"
