---
artifact: ITER_10
status: ready
created: 2026-05-15
scope: CI static checks — ESLint on extension, CSS sync guard, Python syntax check, version/tag assertion, Dependabot
sections_changed: [03, 04]
sections_unchanged: [01, 02, 05]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture
> Unchanged — see ITER_06.md §02

---

## §03 · Tech Stack

No new runtime dependencies.

**New dev dependencies (VSCode extension only):**
- `eslint` — pinned to `^8.0.0` (ESLint 8, legacy config format). ESLint 9 dropped support for `.eslintrc.json` by default and requires a flat config (`eslint.config.js`). ESLint 8 is the current stable choice for projects not yet ready to migrate to flat config, and remains actively maintained under the current LTS policy.
- `eslint-plugin-n` — pinned to `^16.0.0` (compatible with ESLint 8). v17+ requires ESLint 9 flat config and is not compatible with `.eslintrc.json`.

**New config files:**
- `vscode-extension/.eslintrc.json` — ESLint config (legacy format, works with ESLint 8)
- `.github/dependabot.yml` — Dependabot config
- `.github/workflows/ci.yml` — new workflow (push + PR checks)

No changes to the release workflow from ITER_09.

---

## §04 · Backend / CI

### File structure (additions only)

```
project root/
├── .github/
│   ├── dependabot.yml          ← new
│   └── workflows/
│       ├── ci.yml              ← new
│       └── release.yml         ← unchanged from ITER_09
└── vscode-extension/
    ├── .eslintrc.json          ← new
    └── package.json            ← updated: eslint + eslint-plugin-n added
```

---

### ESLint config — `vscode-extension/.eslintrc.json`

```json
{
  "env": {
    "node": true,
    "es2020": true
  },
  "plugins": ["n"],
  "extends": ["eslint:recommended", "plugin:n/recommended"],
  "rules": {
    "no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
    "no-console": "off",
    "n/no-missing-require": "error",
    "n/no-unpublished-require": "off"
  },
  "ignorePatterns": ["node_modules/", "dist/"]
}
```

> **ESLint 8 + `.eslintrc.json`:** this is the legacy config format. It works correctly with `eslint: "^8.0.0"`. Do not upgrade to ESLint 9 without migrating to flat config (`eslint.config.js`) — the two formats are not compatible.

> **`n/no-unpublished-require: off`** — `vscode` is a virtual module injected by the extension host; it will never appear in `node_modules` and must not be flagged as missing.

> **`no-console: off`** — extension code uses `console.log` for debug output; treating it as an error would be noise.

> **`.vscodeignore` and `.eslintrc.json`:** ITER_08's `.vscodeignore` contains `**/eslint*`, which excludes `.eslintrc.json` from the packaged `.vsix`. This is intentional and correct — the config file is a dev tool, not extension runtime.

**`vscode-extension/package.json` — updated scripts and devDependencies:**

```json
{
  "scripts": {
    "lint":        "eslint extension.js",
    "sync-css":    "make sync-css || powershell -ExecutionPolicy Bypass -File ../scripts/sync-css.ps1",
    "prepackage":  "npm run sync-css",
    "package":     "vsce package --out dist/skills-toggle.vsix",
    "install-ext": "code --install-extension dist/skills-toggle.vsix"
  },
  "devDependencies": {
    "@vscode/vsce": "^3.0.0",
    "eslint": "^8.0.0",
    "eslint-plugin-n": "^16.0.0"
  }
}
```

> After adding the new deps, run `npm install` locally and commit the updated `package-lock.json`.

---

### CI workflow — `.github/workflows/ci.yml`

Runs on every push to `main` and on every pull request targeting `main`. Push events on feature branches are not covered by this workflow — developers run checks locally or rely on PRs.

> **Why not `push: branches: ['**']`:** combining `push: branches: ['**']` with `pull_request: branches: [main]` causes all jobs to run twice for PRs targeting `main` — once for the push event and once for the PR event. Restricting the push trigger to `main` avoids this and keeps CI costs predictable.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:

  # ── 1. Python syntax check ─────────────────────────────────────────
  python-syntax:
    name: Python syntax check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Check syntax
        run: python3 -m py_compile html/server.py

  # ── 2. CSS sync guard ──────────────────────────────────────────────
  css-sync:
    name: CSS sync check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Sync CSS
        run: cp html/styles.css vscode-extension/webview/styles.css
      - name: Assert no diff
        run: |
          git diff --exit-code vscode-extension/webview/styles.css || {
            echo "ERROR: vscode-extension/webview/styles.css is out of sync with html/styles.css"
            echo "Run: make sync-css"
            exit 1
          }

  # ── 3. ESLint ──────────────────────────────────────────────────────
  lint-extension:
    name: ESLint — extension.js
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json
      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci
      - name: Lint
        working-directory: vscode-extension
        run: npm run lint

  # ── 4. Version / tag assertion ─────────────────────────────────────
  #    Only runs on push events where the ref is a version tag (v*.*.*).
  #    Skipped on PRs and untagged branch pushes.
  #    Fires before the release workflow, so a version mismatch fails CI
  #    before any artifact is produced.
  version-tag:
    name: Version matches release tag
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Assert package.json version matches tag
        run: |
          TAG="${GITHUB_REF_NAME#v}"          # strip leading 'v': v0.1.0 → 0.1.0
          PKG=$(node -p "require('./vscode-extension/package.json').version")
          if [ "$TAG" != "$PKG" ]; then
            echo "ERROR: tag is v${TAG} but package.json version is ${PKG}"
            exit 1
          fi
          echo "OK: tag and package.json both at ${PKG}"

  # ── 5. vsce package check (dry run) ───────────────────────────────
  #    Ensures the extension packages cleanly on every PR and push to main.
  #    The .vsix is discarded — this is a build validation only.
  #    The release workflow (ITER_09) handles the actual artifact upload.
  package-check:
    name: vsce package check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json
      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci
      - name: Sync CSS
        run: cp html/styles.css vscode-extension/webview/styles.css
      - name: Package
        working-directory: vscode-extension
        run: |
          mkdir -p dist
          npx vsce package --out dist/skills-toggle.vsix
```

> **`version-tag` job — explicit Node setup:** the `node -p "require(...)"` call requires Node.js. While Node is available by default on `ubuntu-latest`, the `actions/setup-node` step is included explicitly for clarity and to ensure version consistency with the rest of the workflow.

> **`package-check` — `mkdir -p dist`:** `vsce package --out dist/...` fails if `dist/` does not exist. The directory is gitignored and absent after a fresh checkout.

> **`package-check` — `npx vsce` not `npm run package`:** same reasoning as ITER_09 — the `prepackage` hook calls `make sync-css` which may not be available on CI. CSS is synced in the prior step; `npx vsce` is called directly.

---

### Dependabot — `.github/dependabot.yml`

```yaml
version: 2
updates:
  # VSCode extension npm dependencies
  - package-ecosystem: npm
    directory: /vscode-extension
    schedule:
      interval: weekly
      day: monday
    open-pull-requests-limit: 5
    labels:
      - dependencies
    ignore:
      # Major version bumps for vsce and eslint require manual review.
      # vsce: packaging behaviour can change significantly between majors.
      # eslint: major bump to v9 requires migration to flat config format.
      - dependency-name: "@vscode/vsce"
        update-types: ["version-update:semver-major"]
      - dependency-name: "eslint"
        update-types: ["version-update:semver-major"]
      - dependency-name: "eslint-plugin-n"
        update-types: ["version-update:semver-major"]

  # GitHub Actions
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
      day: monday
    open-pull-requests-limit: 5
    labels:
      - dependencies
```

> **Three major-version ignores:** `@vscode/vsce` (packaging behaviour changes), `eslint` (v9 requires flat config migration — a deliberate manual step), and `eslint-plugin-n` (v17+ is ESLint 9 only — must be upgraded together with `eslint`). Minor and patch updates for all three are automatic.

> **No `pip` ecosystem entry:** `server.py` uses only stdlib — there are no `requirements.txt` or `pyproject.toml` files for Dependabot to track.

---

## §05 · Frontend
> Unchanged — see ITER_08.md §05

---

## Deferred

- ESLint coverage of `index.html` and `panel.html` inline scripts — embedded scripts cannot be linted by ESLint directly without an HTML plugin. Deferred; the most critical logic lives in `extension.js`.
- Migration to ESLint 9 flat config — a deliberate manual step, blocked by Dependabot ignore rule. Deferred.
- `--max-warnings 0` flag on ESLint — currently warnings are allowed (e.g. unused vars). Tightening to zero is a future clean-up task.
- Python linting (`ruff` or `flake8`) — useful as `server.py` grows. Deferred until it justifies the extra dep.
- Smoke test and cross-platform matrix — see ITER_11.
