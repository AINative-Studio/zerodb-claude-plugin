# Contributing to ZeroDB Memory

Thanks for your interest in improving this plugin. This guide covers how to
report issues, propose changes, and run the test suite locally.

## Reporting a bug or requesting a feature

Please [open an issue](https://github.com/AINative-Studio/zerodb-claude-plugin/issues)
before submitting a pull request, so the change can be discussed first. Include:

- What you expected to happen vs. what actually happened
- Steps to reproduce (for bugs)
- Your Claude Code version and OS, if relevant

## Making a change

1. Fork the repo and create a branch off `main`:
   ```shell
   git checkout -b fix/123-short-description
   ```
2. Make your change. Keep pull requests focused — one fix or feature per PR.
3. Reference the issue your change addresses in the PR description
   (`Closes #123` or `Refs #123`).
4. Open a pull request against `main`.

## Running tests locally

This repo has three layers of CI checks (see `.github/workflows/ci.yml`):

### 1. Plugin structure validation

Checks `.claude-plugin/plugin.json` is valid and required fields are present,
that every skill under `skills/` has frontmatter, and that hook scripts are
executable and referenced correctly. No setup required — these are plain
shell/Python checks you can read directly in `ci.yml` and run the same
commands locally.

### 2. MCP smoke test

Verifies the pinned `ainative-zerodb-memory-mcp` npm package is installable.
Requires Node.js; no credentials needed.

### 3. End-to-end tests (live API)

```shell
pip install -r requirements-test.txt
pytest tests/e2e -v
```

These tests hit a real ZeroDB project and require `ZERODB_API_KEY` and
`ZERODB_PROJECT_ID` to be set in your environment. If you don't have a
ZeroDB account yet, the plugin's own auto-provisioning flow
(`lib/ensure-credentials.sh`) can create a free trial project for local
testing — see the README's **Auth** section.

## Code style

- Shell scripts (`hooks/`, `lib/`, `bin/`) should pass `shellcheck` where
  practical.
- Skill files (`skills/*/SKILL.md`) must have valid YAML frontmatter with at
  least `name` and `description`.
- Keep changes surgical — avoid rewriting unrelated code in the same PR as a
  bug fix or feature.

## Code of Conduct

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you're expected to uphold it.
