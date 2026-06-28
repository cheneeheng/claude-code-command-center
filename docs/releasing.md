# Releasing

This monorepo releases on **two independent axes**, distinguished by the git tag namespace:

| Axis | Tag form | Example | Triggers | Release notes from |
|------|----------|---------|----------|--------------------|
| **Component** | `<alias>-vX.Y.Z` | `pppt-v0.9.1` | that component's release workflow | the component's `CHANGELOG.md` |
| **Whole repo** | `vX.Y.Z` | `v0.1.0` | the repo release workflow | the root `CHANGELOG.md` |

The bare `v*` namespace never matches a prefixed `<alias>-v*` tag, so the two axes never collide.
Each component versions independently in its own manifest and changelog; a whole-repo release is a
coherent snapshot of the tree.

## Component aliases

Each independently releasable component owns a short tag prefix. Register a new one by adding a row
here and a release workflow under `.github/workflows/`.

| Alias | Component | Version manifest | Release workflow |
|-------|-----------|------------------|------------------|
| `pppt` | `apps/per-project-plugin-toggler` (VSCode extension) | `apps/per-project-plugin-toggler/vscode-extension/package.json` | `.github/workflows/release-extension.yml` |

## Cutting a component release

Worked example: the plugin toggler (`pppt`).

1. **Bump the version** in the component's manifest (`vscode-extension/package.json`) following
   SemVer (MAJOR breaking / MINOR feature / PATCH fix; when unsure, PATCH).
2. **Update the component's `CHANGELOG.md`** — move `[Unreleased]` items into a new
   `## [X.Y.Z] - YYYY-MM-DD` section.
3. **Commit** the bump + changelog (e.g. `chore: release pppt-vX.Y.Z`), via a PR, and merge to
   `main`.
4. **Tag the merge commit on `main`** and push:
   ```bash
   git checkout main && git pull origin main
   git tag -a pppt-vX.Y.Z -m "pppt-vX.Y.Z — <summary>"
   git push origin pppt-vX.Y.Z
   ```
   The tag **must** equal the manifest version — `release-extension.yml` asserts this and fails
   otherwise.
5. The workflow builds the `.vsix` and attaches it to the GitHub release for the tag. It does
   **not** publish to the VSCode Marketplace (that would need `npx vsce publish` + a `VSCE_PAT`
   secret).

## Cutting a whole-repo release

Not yet wired (no `release-repo.yml`). When the repo cuts its first repo-wide release, add a root
`CHANGELOG.md` and a workflow triggered on `push: tags: ['v*']`, then tag `vX.Y.Z` on `main`.
