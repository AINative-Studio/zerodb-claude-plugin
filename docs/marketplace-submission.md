# Marketplace Submission — zerodb-memory

This document tracks the submission of `zerodb-memory` to the Anthropic official plugin marketplace, and documents the self-hosted AINative marketplace that is available immediately.

---

## Anthropic Official Marketplace Submission Entry

The following JSON entry is ready to submit to `anthropics/claude-plugins-official`:

```json
{
  "name": "zerodb-memory",
  "description": "Persistent cross-session memory for Claude Code, powered by ZeroDB. Automatically stores what Claude learns each session and recalls it next time — architecture decisions, bugs, conventions, and code ownership.",
  "author": {
    "name": "AINative Studio"
  },
  "category": "productivity",
  "homepage": "https://ainative.studio/products/zerodb",
  "tags": ["memory", "context", "zerodb", "ainative"],
  "source": {
    "source": "github",
    "repo": "AINative-Studio/zerodb-claude-plugin",
    "ref": "main"
  }
}
```

---

## Submission Steps

1. **Fork the official registry**
   ```
   gh repo fork anthropics/claude-plugins-official
   ```

2. **Clone your fork and create a branch**
   ```bash
   git clone https://github.com/<your-org>/claude-plugins-official
   cd claude-plugins-official
   git checkout -b add-zerodb-memory
   ```

3. **Add the entry to `marketplace.json`**

   Open `marketplace.json` and append the submission entry above into the `plugins` array.

4. **Commit and push**
   ```bash
   git add marketplace.json
   git commit -m "Add zerodb-memory plugin from AINative Studio"
   git push origin add-zerodb-memory
   ```

5. **Open a pull request**

   Go to `https://github.com/anthropics/claude-plugins-official` and open a PR from your fork's `add-zerodb-memory` branch targeting `main`.

   PR title: `Add zerodb-memory — persistent cross-session memory for Claude Code`

   Include in the PR body:
   - Plugin name and purpose
   - Link to `https://ainative.studio/products/zerodb`
   - Link to `https://github.com/AINative-Studio/zerodb-claude-plugin`
   - Confirmation that the pre-submission checklist below is complete

---

## Install Commands

### After Anthropic approval (official marketplace)

```
/plugin install zerodb-memory@claude-plugins-official
```

### AINative self-hosted marketplace (available immediately)

```
/plugin marketplace add github:AINative-Studio/zerodb-claude-plugin
```

Then install from it:

```
/plugin install zerodb-memory
```

---

## Pre-Submission Validation Checklist

- [ ] Plugin loads without errors in a fresh Claude Code session
- [ ] `plugin.json` (or equivalent manifest) is present at the repo root or in `.claude-plugin/`
- [ ] All skills listed in the manifest exist at their declared paths under `skills/`
- [ ] All hooks listed in the manifest exist at their declared paths under `hooks/`
- [ ] `README.md` documents setup, usage, and required environment variables (`AINATIVE_API_KEY`, `ZERODB_PROJECT_ID`)
- [ ] No credentials, tokens, or secrets are committed to the repository
- [ ] Repository is public at `github.com/AINative-Studio/zerodb-claude-plugin`
- [ ] `homepage` URL (`https://ainative.studio/products/zerodb`) is reachable
- [ ] Plugin works end-to-end: memory is stored in one session and recalled in a subsequent session
- [ ] `version` in `marketplace.json` matches the latest release tag
- [ ] Plugin category is set to `"productivity"`
- [ ] `tags` include `["memory", "context", "zerodb", "ainative"]`
- [ ] `author.name` is `"AINative Studio"` (consistent with GitHub org)
