---
artifact: ITER_09
status: ready
created: 2026-05-15
scope: GitHub Actions CI — package the VSCode extension and attach the .vsix to GitHub releases automatically
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

**New CI tooling:**
- `GitHub Actions` — the workflow runner. No self-hosted runners; uses `ubuntu-latest`.
- `@vscode/vsce` — already added as a dev dependency in ITER_08. The CI job invokes it via `npx vsce` directly, bypassing the `npm run package` wrapper (see note below).
- `softprops/action-gh-release` — a community action (`v2`) for attaching files to GitHub Releases. Pinning to a full commit SHA recommended before first production release (see below).

No changes to `make`, Python, or Node.js version requirements from prior iterations.

---

## §04 · Backend / CI

### File structure (additions only)

```
project root/
├── .github/
│   └── workflows/
│       └── release.yml     ← new
└── vscode-extension/
    └── package.json        ← minor update: add `engines.node` field
```

---

### Workflow — `.github/workflows/release.yml`

**Trigger:** fires when a GitHub Release is published (the `released` activity type, not `created` or `prereleased` — only fully published releases get the artifact attached).

**Job:** single job `package-and-upload`, runs on `ubuntu-latest`.

```yaml
name: Release — package VSCode extension

on:
  release:
    types: [released]

permissions:
  contents: write   # required at workflow level for softprops/action-gh-release to upload assets

jobs:
  package-and-upload:
    name: Build .vsix and attach to release
    runs-on: ubuntu-latest

    steps:
      # 1. Check out the repo at the tagged commit
      - name: Checkout
        uses: actions/checkout@v4

      # 2. Set up Node.js — version matches what VSCode bundles (~20 LTS)
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json

      # 3. Install dev dependencies (@vscode/vsce and any others)
      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci

      # 4. Sync CSS from html/ into the webview directory.
      #    Runs cp directly — avoids invoking 'make' which may not be on the runner.
      #    This step must come before packaging so vsce picks up the current CSS.
      - name: Sync CSS
        run: cp html/styles.css vscode-extension/webview/styles.css

      # 5. Create output directory and package the extension.
      #    Uses 'npx vsce' directly rather than 'npm run package' to avoid
      #    triggering the prepackage script, which calls 'make sync-css' and
      #    would fail because make may not be installed on the runner.
      - name: Package extension
        working-directory: vscode-extension
        run: |
          mkdir -p dist
          npx vsce package --out dist/skills-toggle.vsix

      # 6. Attach the .vsix to the GitHub Release that triggered the workflow
      - name: Upload .vsix to release
        uses: softprops/action-gh-release@v2
        with:
          files: vscode-extension/dist/skills-toggle.vsix
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **`permissions: contents: write`** is declared at the workflow level. This grants the `GITHUB_TOKEN` write access to repository contents, which `softprops/action-gh-release` needs to upload release assets. The `GITHUB_TOKEN` is also passed explicitly via `env:` on the upload step to make the dependency unambiguous — some configurations of the action require it.

> **Why `npx vsce` not `npm run package`:** the `package` script in `package.json` has a `prepackage` hook (from ITER_08) that runs `npm run sync-css`, which internally calls `make sync-css`. `make` is not guaranteed on CI runners and would fail. Since CSS is already synced in step 4, calling `npx vsce` directly bypasses the hook safely. The `prepackage` hook is for local development only.

> **`mkdir -p dist`:** `vsce package --out dist/...` fails if the `dist/` directory does not exist. The directory is in `.gitignore` and will not be present after a fresh checkout.

> **Pinning `softprops/action-gh-release`:** for production use, pin to a full commit SHA instead of the `v2` tag to prevent tag-mutable supply-chain attacks:
> ```yaml
> uses: softprops/action-gh-release@c062e08bd532815e2082a7e09a79d557e0e6042a  # v2.2.1
> ```
> The SHA above is illustrative — verify the latest release SHA at https://github.com/softprops/action-gh-release/releases before committing.

---

### `vscode-extension/package.json` — minor update

Add `engines.node` so CI and local environments use a compatible version:

```json
{
  "engines": {
    "vscode": "^1.80.0",
    "node": ">=20"
  }
}
```

Also ensure `package-lock.json` is committed — `npm ci` requires it. If it doesn't exist yet, run `npm install` locally once and commit the lockfile.

---

### Release naming convention

The `.vsix` filename is fixed (`skills-toggle.vsix`) — it does not embed the version number. This keeps download URLs stable.

If versioned filenames are preferred in future (e.g. `skills-toggle-0.1.0.vsix`), the package step can be updated:

```yaml
- name: Package extension
  working-directory: vscode-extension
  run: |
    mkdir -p dist
    VERSION="${GITHUB_REF_NAME#v}"   # strip leading 'v': v0.1.0 → 0.1.0
    npx vsce package --out "dist/skills-toggle-${VERSION}.vsix"
```

Deferred — flat name is sufficient for now.

---

### What the workflow does NOT do

- **Publish to VS Marketplace** — `vsce publish` requires a PAT stored as a repository secret and a registered publisher. Out of scope; local `.vsix` install is the only distribution channel right now.
- **Run tests** — no automated tests yet. A `ci.yml` workflow is introduced in ITER_10.
- **Version bump** — the `version` field in `package.json` must be updated manually before tagging a release. Automated version bumping is deferred.
- **Build the HTML version** — `server.py` and `index.html` are plain files with no build step; they require no CI artifact.

---

## §05 · Frontend
> Unchanged — see ITER_08.md §05

---

## Deferred

- Pinning `softprops/action-gh-release` to a full SHA — recommended before first production release.
- Versioned `.vsix` filenames — deferred; flat name is fine for local distribution.
- VS Marketplace publish — requires publisher PAT and registration; deferred indefinitely.
- Automated version bump on tag — deferred.
- Cross-platform packaging matrix — see ITER_11.
