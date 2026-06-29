# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Vantage is a local, serverless repo explorer. Point it at a folder full of Git repos
and it renders each immediate subfolder as a card, lets you expand a card into its file
tree, pick one file from two different repos, diff them in a slide-in sidebar, and
copy/overwrite one onto the other. Each expanded card can also open its repo in VSCode.
Core flow: **open → find two repos → compare a file → copy across.**

## Running, building, testing

See README.md for end-user setup (folder picker, the optional "Set root path" for VSCode links).
Facts that constrain edits:

- **No build step, no package manager, no dependencies, no tests.** The app is a set of
  **static files**: `index.html` (markup + ordered tags), `styles/*.css`, and `scripts/*.js`,
  loaded as classic `<link>`/`<script>`. v1 was a three-file split, v2 collapsed it into a
  single inlined `index.html`, and **v3 re-split it** into several small classic-script files
  (one concern per file) wired by load order — see the constraints below.
- Runs from `file://` in **Chrome / Edge / Opera** only — it depends on the File System Access
  API, so it will not work in Firefox or Safari. The picked directory handle is persisted in
  IndexedDB (reopening reconnects, subject to a browser permission re-grant click).

## Hard architectural constraints (do not violate)

These are deliberate decisions, not accidents — they are documented in this file and in the
repo-root archived decision log (`.agents_workspace/archive/decision-log.md`). Read them
before proposing changes that touch them:

- **Multiple files, classic `<script>`/`<link>`, never `type="module"`.** The app is split
  into `styles/{tokens,layout,components}.css` and `scripts/*.js`, loaded by classic
  `<link>`/`<script src>` tags. ES-module `import`/`export` is CORS-blocked over `file://`,
  so cross-file sharing goes through the single `window.Vantage` namespace object instead,
  and **load order in `index.html` is the dependency contract** (`scripts/namespace.js`
  first, `scripts/app.js` last; a module must be listed after anything it uses). Do not
  introduce ES modules, a bundler, or a server, and do not re-inline everything back into
  one file.
- **No network calls of any kind.** No CDN, no fetch to remote hosts, no analytics. The
  brand sheet's Google-Fonts `@import` was intentionally dropped for this reason; the type
  tokens in `styles/tokens.css` fall back to Georgia / system-ui / monospace. Do not
  reintroduce remote fonts or assets.
- **No new dependencies.** The line-based diff is hand-written (LCS); keep it that way.
- **Writes are confined to the chosen root folder.** Copy/overwrite is the only
  destructive action and must always name the exact target and wait for an explicit
  confirm (the `#confirm-overlay` modal). There is no delete capability.
- **Last-activity is a proxy, not precision.** Activity time comes from file mtimes
  (`.git/logs/HEAD` → `.git/HEAD` → shallow working-tree walk). Never parse git commit
  objects or pack files.

## Code structure

`index.html` holds the static markup with fixed mount-point IDs, then the ordered `<link>`
and `<script>` tags. CSS is split across `styles/` (`tokens.css` brand `:root` tokens →
`layout.css` positioning → `components.css` visual treatment). JS is split across `scripts/`,
each file a plain object attached to `window.Vantage` (no classes), loaded in this order:

- **`namespace.js`** (FIRST) — `window.Vantage = {}` plus shared constants (`IGNORE_LIST`,
  `STACK_MARKERS`, `FALLBACK_WALK_MAX_DEPTH`).
- **`persist.js` → `Vantage.Persist`** — IndexedDB: `saveHandle`/`loadHandle` (directory
  handle, survives sessions), `saveCache`/`loadCache` (scan results), and `saveRootPath`/
  `loadRootPath` (the optional absolute path used only to build VSCode links).
- **`scanner.js` → `Vantage.Scanner`** — `chooseRoot()` opens the picker; `scanRoot(dirHandle)`
  enumerates child dirs as repos (per-repo metadata gathered in parallel); `detectStack` reads
  marker files (`package.json`→Node, `Cargo.toml`→Rust, etc.); `lastActivity` runs the mtime
  fallback chain; `readTree`/`readChildren` lazily build a repo's file tree on expand. Respects
  `Vantage.IGNORE_LIST`.
- **`compare.js` → `Vantage.Compare`** — `diff(textA, textB)` (line-based LCS → `DiffLine[]`)
  and `looksBinary` (skip diffing binary files).
- **`copy.js` → `Vantage.Copy`** — `copyFile(srcFileHandle, dstDirHandle, name)` and
  `resolveDestDir`/`destExists`, behind the overwrite confirm.
- **`editor.js` → `Vantage.Editor`** — `vscodeUri(repoName)` composes
  `vscode://file/<rootPath>/<repoName>` (normalizing slashes / Windows drive letters) from an
  internal `rootPath` kept in sync via `setRootPath`; returns `null` when no root path is set,
  which keeps the "Open in VSCode" button disabled.
- **`ui.js` → `Vantage.UI`** — the controller and all UI: in-memory state (`repos`,
  `selection`, `filterText`, `sortMode`, `sidebarMode`, `lastDiff`, `activeRepoName`, …), DOM
  refs cached in `UI.el`, event binding, and all rendering (`renderBoard`, `buildRepoCard`,
  `renderTreeNode`, `buildVscodeButton`, the selection bar, the slide-in diff sidebar + floating
  puck, root-path/confirm modals, toasts). The board has a sort control (last-activity / A–Z /
  stack); there is **no** jump-to-repo search.
- **`app.js`** (LAST) — the only file that touches the DOM on boot: `Vantage.UI.init()` on
  `DOMContentLoaded`.

Data flows one way: Scanner/Persist produce plain in-memory objects (`Repo`, `TreeNode`,
`Selection`, `SidebarState` — plain-object shapes), `Vantage.UI` holds them
as state and re-renders the relevant region. The markup has fixed mount-point IDs that
`UI.cacheDom()` looks up; regions, the sidebar, and the puck are toggled via the `hidden`
attribute and class toggles, not routing.

Two v3-specific surface rules: the diff sidebar has only **`open | minimized`** modes — there is
**no close/dismiss control**; minimize is presentation-only and never clears the selection, and
the only way to remove the comparison surface is to **Clear** the selection (in the selection
bar). Board cards carry **derived** highlight classes recomputed each render — `.is-compare-a` /
`.is-compare-b` (a repo contributes side A/B, shown with an A/B badge) and `.is-active` (the
card given **visual focus**); none of this is persisted. Selection is decoupled from expansion:
clicking anywhere on a card sets `.is-active` (a second click, or a click on empty space, clears
it — purely cosmetic, it never touches the A/B comparison), while only the chevron expands the
card (which also force-selects it). **Swap** reorders A/B without reopening a minimized sidebar.

## Conventions

- The current design is the **v3 multi-file reshape** described in the sections above; the
  v1 (three-file) and v2 (single-file) designs are superseded and live only in git history.
- Agent decisions are archived at the repo-root `.agents_workspace/archive/decision-log.md`;
  new decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
- Section banners in the scripts use `/* ===== ... ===== */`; each file is one cohesive
  module attached to `window.Vantage`. Match that style — no frameworks, no classes, no JSX.
