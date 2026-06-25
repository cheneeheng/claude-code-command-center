---
artifact: SKELETON_v3
status: ready
created: 2026-06-14
app: Vantage — local repo explorer (v3)
stack: HTML, CSS (brand tokens), vanilla JS (classic scripts, multi-file), File System Access API, IndexedDB
sections: [01, 02, 03, 05]
---

# Vantage v3 — Skeleton Plan

> §04 (Backend) and §06 (LLM/Prompts) are intentionally omitted: Vantage has no
> server and no LLM. Everything runs client-side from static files.
>
> This skeleton is **self-contained** — it re-states every section v3 needs. v3
> reshapes the package from v2 (one inlined `index.html` → several small classic-script
> files) and tightens two surfaces (sidebar can no longer be dismissed; the board
> highlights selection state). It does **not** point back into the v1/v2 families;
> lineage is conceptual only.

---

## §01 · Concept

Vantage is a local, serverless repository explorer for someone who has accumulated
many (100+) unrelated Git repos in one folder and can no longer get a usable overview
from the filesystem or the GitHub web UI. Every repo is a card on a single board,
filterable so the right one is fast to find; a card expands into its file tree, and
picking a file from two different repos shows them diffed in a slide-in right-hand
sidebar and lets you copy/overwrite one onto the other. **v3 reshapes the package and
two surfaces:** the tool is now split into several small static files (classic
`<script>`/`<link>`, still no server and no build), the diff sidebar can only be
**open or minimized to a floating puck** — there is no close/dismiss — and the board
**highlights** which repos are part of the active comparison. The single most important
flow is unchanged: **open the tool → find two repos → compare a file → copy it across.**

---

## §02 · Architecture

### Packaging change (the reshape this version is about)

v2 was one inlined `index.html`. v3 splits it into several small files wired with
**classic `<script src>` and `<link>`** — no ES modules, no bundler, no build step.
This keeps the double-click-`file://` run story: classic scripts and stylesheets load
fine from `file://`, whereas ES-module `import`/`export` is CORS-blocked there. Modules
share a single global namespace object (`window.Vantage`) instead of `import`/`export`,
and **load order in `index.html` is the dependency contract** (a module must be listed
after anything it uses).

### File layout (all static, served by nothing)

```
index.html              markup + mount points; ordered <link>/<script> tags
styles/
  tokens.css            brand :root custom properties (+ neutral fallbacks)
  layout.css            page / board grid / sidebar / puck positioning
  components.css        cards, file tree, diff rows, buttons, highlight states
scripts/
  namespace.js          window.Vantage = {}            (loaded FIRST)
  persist.js            Vantage.Persist                (IndexedDB)
  scanner.js            Vantage.Scanner                (scan / tree / activity / stack)
  compare.js            Vantage.Compare                (diff)
  copy.js               Vantage.Copy                   (overwrite-confirmed write)
  editor.js             Vantage.Editor                 (vscode:// URI)
  ui.js                 Vantage.UI                     (board, tree, sidebar, puck, highlights, render)
  app.js                bootstrap: wire DOM, kick off load (loaded LAST)
```

The split mirrors the module table below; "smaller files" = one concern per file. The
exact number of `.js`/`.css` files can be tuned in iteration, but the **rules are
fixed**: classic scripts only, one global namespace, explicit load order.

### Component diagram (all client-side)

```
                    index.html  (mount points + ordered tags)
                         │
   ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐
   │ Scanner │ → │  Board   │ → │ TreeView │ → │ Selection  │
   └─────────┘   └──────────┘   └──────────┘   └────────────┘
        │             │ filter        │ expand      │ A / B
        ▼             ▼               ▼             ▼
   ┌─────────┐                              ┌──────────────┐
   │ Persist │  (IndexedDB)                 │ Diff Sidebar │  (open | minimized)
   └─────────┘                              └──────────────┘
        │                                          │
        ▼                                          ▼
   handle + cache + rootPath              ┌──────────────┐    vscode://file/...
                                          │   Copy       │    (OS handler)
                                          └──────────────┘
```

### Internal surface (function modules, no HTTP)

| Module    | Function (shape)                              | Description                                   |
|-----------|-----------------------------------------------|-----------------------------------------------|
| Scanner   | `scanRoot(dirHandle) → Repo[]`                | Enumerate repos + metadata, write cache       |
| Scanner   | `readTree(repo) → TreeNode`                   | Lazy file tree for one repo (ignore-listed)   |
| Scanner   | `lastActivity(repoHandle) → epoch ms`         | `.git/logs/HEAD` mtime, with fallback chain   |
| Scanner   | `detectStack(repoHandle) → string[]`          | Marker-file detection in repo root            |
| Compare   | `diff(textA, textB) → DiffLine[]`             | Line-based diff, computed in JS (hand-rolled) |
| Sidebar   | `openSidebar() / minimize()`                  | View-state of the diff panel (no close)       |
| Copy      | `copyFile(srcHandle, dstDirHandle, name)`     | Overwrite-confirmed write                     |
| Editor    | `vscodeUri(repoName) → string`                | Compose `vscode://file/<root>/<name>`         |
| Persist   | `saveHandle / loadHandle / saveCache / saveRootPath / loadRootPath` | IndexedDB read/write |

No auth, no network, no queues — none are needed.

### Data model (in-memory objects + IndexedDB)

- **Repo** — `{ name, dirHandle, stack[], lastActivity (epoch ms), fileTree? }`
  (`fileTree` populated lazily on expand)
- **TreeNode** — `{ name, kind: 'file'|'dir', handle, children? }`
- **Selection** — `{ sideA: {repoName, path, handle} | null, sideB: {repoName, path, handle} | null }`
  — `repoName` is the repo's name **string** (the unique board key, since repos are
  direct children of the root), used for highlight matching and the diff header; `handle`
  is the file handle. Only a new file pick changes it; sidebar minimize never clears it.
- **SidebarState** — `{ mode: 'open' | 'minimized' }` — **view-only, not persisted**.
  The `'closed'` mode from v2 is **removed**; there is no dismiss path. `mode` is only
  consulted once **both** selection sides are set: before that, neither the panel nor the
  puck is shown, and `mode` defaults to `'open'` the moment a comparison first completes.
- **Board highlight state** — *derived, not stored.* Computed each render from
  `Selection` + the active card (see §05). No new persisted entity.
- **Persisted (IndexedDB)** — the root `dirHandle`, the scan cache, and an optional
  `rootPath` string used only to build VSCode links.

---

## §03 · Tech Stack

- **Runtime:** the browser. **Chromium-based only** (Chrome / Edge / Opera) — the
  File System Access API is unavailable in Firefox and Safari.
- **Language:** vanilla JavaScript, loaded as **classic `<script>` files, not
  `type="module"`** — so the page works opened directly as `file://` without a server
  (ES-module `import` between files is CORS-blocked over `file://`). Cross-file sharing
  is via the `window.Vantage` namespace object, not `import`/`export`.
- **Markup/Style:** plain HTML + multiple CSS files via `<link>`. **Brand CSS** supplies
  design tokens (colours, type, spacing) as `:root` custom properties referenced by the
  component CSS. No framework, no build step, no CDN.
- **Files:** several small static files (see §02 layout) — no single-file constraint and
  no bundling. **Load order is the dependency contract;** `namespace.js` first, `app.js`
  last.
- **Dependencies:** none. The diff is hand-written (~40–50 lines, line-based).
- **Brand-CSS caveat:** if the brand sheet pulls fonts/assets via `@import`/CDN, that
  reintroduces a network dependency; to stay offline-capable, embed or fall back to
  system fonts. (Resolve in iteration if going fully offline is required.)

---

## §05 · Frontend

### Screens

Single page, regions (no routing):

1. **Board** — landing view. Brand-styled header with a **board filter** (narrows which
   repo cards are visible) and a grid of repo cards sorted by last activity. There is
   **no** jump-to-repo / Ctrl+F navigate search (removed in v2, stays removed). Cards
   carry **highlight states** (below) that reflect the current comparison.
2. **Card-expanded** — a card opens to show that repo's file tree; clicking a file
   assigns it to selection side A or B. The expanded card also carries an **Open in
   VSCode** button (disabled until a root path is set; see stub strategy).
3. **Diff Sidebar** — a right-hand panel that **slides in** when both selection sides are
   set (before that, neither panel nor puck is shown). It has exactly two modes: **open**
   (panel visible) and **minimized** (collapsed to a small floating **puck** fixed to the
   screen edge that re-opens on click). **There is no close/× control** — the sidebar can
   never be dismissed, only minimized. Selection is never cleared by minimizing. The panel
   also carries the **copy action** (copy A→B / B→A, confirm-on-overwrite).

### Board highlight states (new in v3)

Two visually distinct treatments on `RepoCard`, both **derived each render** — no new
state to persist:

- **Compare-source** — the repo owns side A and/or side B of the current `Selection`
  (i.e. one or more of its files is picked for comparison). Distinguish A vs B with a
  small badge so it's clear which side a repo contributes. This is the primary ask
  ("repos where one or more files have been selected for comparison").
- **Active/selected repo** — the currently expanded/focused card. Interpreted as "the
  repo you're drilling into" (resolved in ITER_02_v3, which owns selection). If "selected"
  is later meant as a distinct, explicit repo-pick action rather than "expanded," only the
  `.is-active` trigger changes — the skeleton already reserves the class and state.

Skeleton ships these as CSS state classes (e.g. `.is-compare-a`, `.is-compare-b`,
`.is-active`) with the visual treatment stubbed; live wiring to `Selection` lands in an
iteration.

### Component tree (top-level)

```
App
├── Header (brand) — BoardFilter
├── Board — RepoCard*  (each: summary + expand + highlight classes)
│     └── ExpandedCard — FileTree, OpenInVSCodeButton (stub)
├── DiffSidebar (slide-in; modes: open | minimized)
│     ├── SidebarHeader — MinimizeButton   (no CloseButton)
│     ├── DiffView (stub)
│     └── CopyBar (stub) — Copy A→B / B→A, confirm-on-overwrite
└── FloatingPuck (shown only while SidebarState.mode === 'minimized')
```

### Placeholder / stub strategy

- **Multi-file scaffold:** all files exist and load in order; `index.html` mounts every
  region. JS modules attach to `window.Vantage` but ship as stubs (Scanner returns
  placeholder repos, `diff` returns a placeholder line set) so the page renders end to
  end before real wiring.
- **Diff sidebar:** renders its chrome and animates open/minimize on real selection
  state, but `DiffView` shows a placeholder ("diff renders here") and the **CopyBar**
  buttons are present-but-disabled until their iterations wire them.
- **Highlight states:** classes are defined and styled; the derivation from `Selection`
  is stubbed (e.g. a hardcoded example card) until wired in iteration.
- **Open in VSCode:** button present but **disabled** with a tooltip ("set root path to
  enable") until the root-path entry + URI are wired.
- **Brand CSS:** ships with brand tokens in `tokens.css`; if the real brand sheet isn't
  supplied yet, neutral fallback values fill the `:root` block so the page still renders.

### How to run locally

Open `index.html` directly in Chrome/Edge (double-click, or `file://` URL) — no server,
no build. On first run, click **Change folder** to pick the projects root via the OS
picker; the directory handle is stored in IndexedDB, so subsequent opens don't re-prompt.

---

## Decisions Log (so we don't re-litigate)

- **Multi-file, but classic scripts only.** Split into several small files for
  readability; no ES modules and no build step, so double-click `file://` still works.
  `window.Vantage` namespace + explicit load order replace `import`/`export`.
- **Sidebar can't be dismissed.** Modes collapse from v2's three (`open | closed |
  minimized`) to two (`open | minimized`). The puck is always the way back; there is no ×.
- **Board highlights are derived, not stored.** Computed from `Selection` (+ active card)
  every render — no new persisted entity, no reload-survival requirement.
- **Self-contained skeleton.** Re-states all sections; does not resolve into v1/v2.
- **Carried forward unchanged:** Chrome/Edge only; `.git`-mtime activity proxy (no commit
  parsing); manual root-path entry for VSCode (FSA hides the absolute path); copy/overwrite
  is the only destructive action and stays behind an explicit confirm.

## Explicitly Deferred (not in this skeleton)

- Live wiring of Scanner, diff, copy, VSCode, and the highlight derivation (each lands in
  an iteration; skeleton ships chrome + stubs).
- Whether the sidebar shell is present **before** a comparison exists, or only appears
  once both sides are set (skeleton assumes the latter; ITER can revisit).
- Exact file count / further subdivision of `ui.js`.
- Persisting diff/selection across reloads; editor-agnostic open; nested-repo VSCode
  paths; syntax-highlighted/side-by-side diffs — all still out of scope.
