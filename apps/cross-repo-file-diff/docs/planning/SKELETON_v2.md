---
artifact: SKELETON_v2
status: ready
created: 2026-06-14
app: Vantage — local repo explorer (v2)
stack: HTML, CSS (brand tokens), vanilla JS (classic script), File System Access API, IndexedDB
sections: [01, 02, 03, 05]
---

# Vantage v2 — Skeleton Plan

> §04 (Backend) and §06 (LLM/Prompts) are intentionally omitted: Vantage has no
> server and no LLM. Everything runs client-side in a single static page.
>
> This skeleton is **self-contained** — it re-states every section v2 needs. v2
> reshapes the scaffold from v1 (three files → one file, v1 styling → brand CSS),
> so it does not point back into the v1 family. Lineage to v1 is conceptual only.

---

## §01 · Concept

Vantage is a local, serverless repository explorer for someone who has accumulated
many (100+) unrelated Git repos in one folder and can no longer get a usable overview
from the filesystem or the GitHub web UI. Every repo is a card on a single board,
filterable so the right one is fast to find; a card expands into its file tree, and
picking a file from two different repos shows them diffed and lets you copy/overwrite
one onto the other. **v2 reshapes the package and the surfaces:** the whole tool is
now a single brand-styled `index.html`, the diff appears in a slide-in right-hand
sidebar (closeable, or minimized to a floating puck) instead of an inline panel, the
jump-to-repo search is gone, and each expanded card can open its repo in VSCode. The
single most important flow is unchanged: **open the tool → find two repos → compare a
file → copy it across.**

---

## §02 · Architecture

### Component diagram (all client-side, one page)

```
                         index.html  (one file)
   ┌──────────────────────────────────────────────────────────────┐
   │  <style>  brand tokens + component CSS  (inlined)              │
   │  <script> classic, non-module  (inlined)                      │
   │                                                                │
   │   ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐   │
   │   │ Scanner │ → │  Board   │ → │ TreeView │ → │ Selection  │   │
   │   └─────────┘   └──────────┘   └──────────┘   └────────────┘   │
   │        │             │ filter        │ expand      │ A / B     │
   │        ▼             ▼               ▼             ▼           │
   │   ┌─────────┐                              ┌──────────────┐    │
   │   │ Persist │  (IndexedDB)                 │ Diff Sidebar │    │
   │   └─────────┘                              └──────────────┘    │
   │        │                                          │            │
   │        ▼                                          ▼            │
   │   handle + cache + rootPath              ┌──────────────┐      │
   │                                          │   Copy       │      │
   │                                          └──────────────┘      │
   └──────────────────────────────────────────────────────────────┘
              │                                   │
              ▼                                   ▼
   File System Access API                  vscode://file/...  (OS handler)
```

### Internal surface (function modules, no HTTP)

| Module    | Function (shape)                          | Description                                   |
|-----------|-------------------------------------------|-----------------------------------------------|
| Scanner   | `scanRoot(dirHandle) → Repo[]`            | Enumerate repos + metadata, write cache       |
| Scanner   | `readTree(repo) → TreeNode`               | Lazy file tree for one repo (ignore-listed)   |
| Scanner   | `lastActivity(repoHandle) → epoch ms`     | `.git/logs/HEAD` mtime, with fallback chain   |
| Scanner   | `detectStack(repoHandle) → string[]`      | Marker-file detection in repo root            |
| Compare   | `diff(textA, textB) → DiffLine[]`         | Line-based diff, computed in JS (hand-rolled) |
| Sidebar   | `openSidebar() / closeSidebar() / minimize()` | View-state of the diff panel; selection-safe |
| Copy      | `copyFile(srcHandle, dstDirHandle, name)` | Overwrite-confirmed write                     |
| Editor    | `vscodeUri(repoName) → string`            | Compose `vscode://file/<root>/<name>`         |
| Persist   | `saveHandle / loadHandle / saveCache / saveRootPath / loadRootPath` | IndexedDB read/write |

No auth, no network, no queues — none are needed.

### Data model (in-memory objects + IndexedDB)

- **Repo** — `{ name, dirHandle, stack[], lastActivity (epoch ms), fileTree? }`
  (`fileTree` populated lazily on expand)
- **TreeNode** — `{ name, kind: 'file'|'dir', handle, children? }`
- **Selection** — `{ sideA: {repo, path, handle} | null, sideB: {repo, path, handle} | null }`
  — persists across sidebar close/minimize; only a new file pick changes it.
- **SidebarState** — `{ mode: 'open' | 'closed' | 'minimized' }` — view-only, not persisted.
- **Persisted (IndexedDB)** — the root `dirHandle`, the scan cache, and (new in v2) an
  optional `rootPath` string used only to build VSCode links.

---

## §03 · Tech Stack

- **Runtime:** the browser. **Chromium-based only** (Chrome / Edge / Opera) — the
  File System Access API is unavailable in Firefox and Safari.
- **Language:** vanilla JavaScript, **inlined as a classic `<script>`, not
  `type="module"`** — so the page works opened directly as `file://` without a server
  (ES-module `import` between files is CORS-blocked over `file://`).
- **Markup/Style:** plain HTML + CSS, all inlined into one file. **Brand CSS** supplies
  the design tokens (colours, type, spacing) as `:root` custom properties that the
  component CSS references. No framework, no build step, no CDN.
- **Files (exactly one):** `index.html`. (v1's three-file split is collapsed.)
- **Dependencies:** none. The diff is hand-written (~40–50 lines, line-based).
- **Brand-CSS caveat:** if the brand sheet pulls fonts or assets via `@import`/CDN, that
  reintroduces a network dependency; to stay offline-capable, embed or fall back to
  system fonts. (Decided in ITER scope as needed; flagged here.)

---

## §05 · Frontend

### Screens

Single page, regions (no routing):

1. **Board** — landing view. Brand-styled header with a **board filter** (narrows which
   repo cards are visible) and a grid of repo cards sorted by last activity. There is
   **no** jump-to-repo / ctrl+F navigate search — removed in v2.
2. **Card-expanded** — a card opens to show that repo's file tree; clicking a file
   assigns it to selection side A or B. The expanded card also carries an **Open in
   VSCode** button (functionality stubbed in skeleton; see ITER_02_v2).
3. **Diff Sidebar** — a right-hand panel that **slides in** when both selection sides are
   set. Carries a **close (×)** control and a **minimize** control; minimizing collapses
   it to a small floating **puck** fixed to the screen edge that re-opens on click.
   Selection is **not** cleared by close or minimize. (Slide/close/minimize chrome exists
   in the skeleton; actual diff rendering is wired in ITER_01_v2.)

### Component tree (top-level)

```
App
├── Header (brand) — BoardFilter
├── Board — RepoCard*  (each: summary + expand)
│     └── ExpandedCard — FileTree, OpenInVSCodeButton (stub)
├── DiffSidebar (slide-in)
│     ├── SidebarHeader — CloseButton, MinimizeButton
│     └── DiffView (stub)
└── FloatingPuck (shown only while SidebarState.mode === 'minimized')
```

### Placeholder / stub strategy

- **Diff sidebar:** renders its chrome and animates in/out on the real selection state,
  but `DiffView` shows a placeholder ("diff renders here") until ITER_01_v2.
- **Open in VSCode:** button is present but **disabled** with a tooltip ("set root path
  to enable") until ITER_02_v2 wires the URI + root-path entry.
- **Brand CSS:** skeleton ships with the brand tokens inlined and components referencing
  them; if the real brand sheet isn't supplied yet, neutral fallback values fill the
  `:root` block so the page still renders.

### How to run locally

Open `index.html` directly in Chrome/Edge (double-click, or `file://` URL). On first
run, click **Change folder** to pick the projects root via the OS picker; the directory
handle is stored in IndexedDB, so subsequent opens don't re-prompt.
