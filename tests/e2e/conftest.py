"""
pytest conftest for E2E test suite.
Loads credentials from .env files if environment variables not set.
"""
import os
from pathlib import Path


def pytest_configure(config):
    """Load .env from repo root and core repo root if env vars not set."""
    if os.getenv("ZERODB_API_TOKEN"):
        return  # Already set

    env_paths = [
        Path(__file__).parent.parent.parent / ".env",  # plugin repo root
        Path.home() / "core" / ".env",                  # core repo
        Path("/Users/aideveloper/core/.env"),
    ]

    for env_path in env_paths:
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, val = line.partition("=")
                    key = key.strip()
                    val = val.strip().strip('"').strip("'")
                    if key and not os.getenv(key):
                        os.environ[key] = val
            break
