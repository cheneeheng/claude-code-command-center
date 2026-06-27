---
artifact: SKELETON
status: ready
created: 2026-06-13
app: Vantage — local repo explorer
stack: HTML, CSS, vanilla JS (classic script), File System Access API, IndexedDB
sections: [01, 02, 03, 05]
---

# Vantage — v1 Skeleton Plan

> §04 (Backend) and §06 (LLM/Prompts) are intentionally omitted: Vantage has no
> server and no LLM. Everything runs client-side in a single static page.

---

## §01 · Concept

Vantage is a local, serverless repository explorer for someone who has accumulated
many (100+) unrelated Git repos in one folder and can no longer get a usable overview
from the filesystem or the GitHub web UI. It presents every repo as a card on a single
board, filterable so you can find the one you want fast, and lets you expand a card into
its file tree, pick a file from two different repos, see them diffed side by side, and
copy/overwrite one onto the other. The single most important flow: **open the tool →
find two repos → compare a file → copy it across.**

---

## §02 · Architecture

### Component diagram

```
                    index.html  (markup + mount points)
                         │
          ┌──────────────┼───────────────┐
          │              │               │
     vantage.css     vantage.js      (browser APIs)
                         │
   ┌─────────────────────┼──────────────────────────┐
   │            │             │            │          │
 Scanner    Board UI    Compare UI    Copy/Write   Persist
   │            │             │            │          │
   └──── File System Access API (read/write) ─────────┘
                              │
                        IndexedDB (handle + scan cache)
```

- **Scanner** — given the root directory handle, enumerates immediate child
  directories (each = one repo). Per repo it gathers: name, detected stack,
  last-activity timestamp. Results cached in IndexedDB.
- **Board UI** — renders repo cards, owns the filter/sort state and the Ctrl+K
  search. Lazily asks the Scanner for a repo's file tree only when a card expands.
- **Compare UI** — holds the current two-file selection (side A / side B) and renders
  the diff.
- **Copy/Write** — performs file copy/overwrite, always behind an explicit confirm.
- **Persist** — stores the directory handle and scan cache in IndexedDB so reopening
  the page is instant and doesn't re-prompt for the folder.

### Data model (in-memory objects, not a DB)

- **Repo** — `{ name, dirHandle, stack[], lastActivity (epoch ms), fileTree? }`
  (`fileTree` populated lazily on expand)
- **TreeNode** — `{ name, kind: 'file'|'dir', handle, children? }`
- **Selection** — `{ sideA: {repo, path, handle}, sideB: {repo, path, handle} }`

### Internal surface (function modules, no HTTP)

| Module      | Function (shape)                          | Description                                  |
|-------------|-------------------------------------------|----------------------------------------------|
| Scanner     | `scanRoot(dirHandle) → Repo[]`            | Enumerate repos + metadata, write cache      |
| Scanner     | `readTree(repo) → TreeNode`               | Lazy file tree for one repo (ignore-listed)  |
| Scanner     | `lastActivity(repoHandle) → epoch ms`     | `.git/logs/HEAD` mtime, with fallback chain  |
| Scanner     | `detectStack(repoHandle) → string[]`      | Marker-file detection in repo root           |
| Compare     | `diff(textA, textB) → DiffLine[]`         | Line-based diff, computed in JS              |
| Copy        | `copyFile(srcHandle, dstDirHandle, name)` | Overwrite-confirmed write                    |
| Persist     | `saveHandle / loadHandle / saveCache`     | IndexedDB read/write                         |

No auth, no network, no queues — none are needed.

---

## §03 · Tech Stack

- **Runtime:** the browser. **Chromium-based only** (Chrome / Edge / Opera) — the
  File System Access API is unavailable in Firefox and Safari.
- **Language:** vanilla JavaScript. **Classic `<script>`, not `type="module"`** — so
  the page works opened directly as `file://` without a server (ES-module `import`
  between files is CORS-blocked over `file://`).
- **Markup/Style:** plain HTML + CSS. No framework, no build step, no CDN.
- **Browser APIs used:**
  - File System Access API — `showDirectoryPicker({ mode: 'readwrite' })`, directory
    enumeration, `getFile().lastModified`, `createWritable()`.
  - IndexedDB — persist the directory handle (survives sessions) + scan cache.
- **Files (exactly three):** `index.html`, `vantage.css`, `vantage.js`.
- **Dependencies:** none. The diff is hand-written (~40–50 lines, line-based LCS).

---

## §05 · Frontend

### Screens

Single page, three regions (no routing):

1. **Board** — the landing view. Filter/search bar + grid of repo cards.
2. **Card-expanded** — a card opens to show that repo's file tree; clicking a file
   assigns it to selection side A or B.
3. **Compare panel** — appears once both sides are selected; shows the diff and the
   copy action.

### Component tree (top-level only)

```
App
├── Toolbar
│   ├── SearchPalette   (Ctrl+K — overlay search to find a repo)
│   └── FilterControls  (sort: last-activity | alphabetical | stack)
├── Board
│   └── RepoCard*       (name, stack badges, last-activity)
│       └── FileTree    (lazy; expand-on-open)
└── ComparePanel
    ├── DiffView        (side A vs side B, colored line diff)
    └── CopyBar         (copy A→B / B→A, confirm-on-overwrite)
```

### How to run

Double-click `index.html` (or open it in Chrome/Edge). On first use, click "Choose
folder" and pick the projects root. The handle is remembered for next time.

### Last-activity strategy (the one with real engineering)

Resolved per repo with a cheap fallback chain — **one stat per repo, no tree-walk on
the hot path**, and crucially **no commit-object parsing** (we read file mtimes, never
decode git objects):

1. `getFile().lastModified` of **`.git/logs/HEAD`** — touched on every commit / pull /
   checkout / merge; tight proxy for "last did something here." Primary.
2. mtime of **`.git/HEAD`** — if the reflog is absent.
3. Shallow, ignore-listed walk of the working tree (newest file mtime) — only when
   there's no `.git` at all.

**Ignore-list** (applies to tree reads and the fallback walk): `.git`, `node_modules`,
`venv`, `.venv`, `target`, `dist`, `build`, `.next`, `__pycache__`. Walk depth is
capped on the fallback path.

### Stack detection

Marker files in repo root → badges: `pyproject.toml`/`requirements.txt` → Python,
`package.json` → Node, `Cargo.toml` → Rust, `go.mod` → Go, `pom.xml`/`build.gradle`
→ JVM. A repo can carry multiple badges.

### Filtering / sorting

All client-side over the in-memory repo list: sort by **last-activity**, **alphabetical**,
or **stack**; free-text filter by name. Ctrl+K opens the search overlay (chosen over
Ctrl+F to avoid fighting the browser's native find).

### Placeholder strategy

Before a folder is chosen, the board shows an empty state with the "Choose folder"
prompt. File trees render a lightweight spinner while a repo's tree is read on first
expand.

### Safety commitments

- Localhost/local-file only; no network calls of any kind.
- Writes are confined to the chosen root folder.
- **Copy/overwrite is the only destructive action** — it always names the exact target
  being overwritten and waits for an explicit confirm. No delete capability in v1.

---

## Decisions Log (what we settled, so we don't re-litigate)

- **No Python server.** Dropped once accurate git commit timestamps left scope; the
  File System Access API covers read + write from a static page.
- **Board of cards**, not the old two-pane layout. Card expands to a file tree;
  selection of the two compare files lives across the board.
- **Time is for finding, not precision.** Folder/`.git`-mtime proxy is fine; we do
  **not** parse commit objects or pack files.
- **Ctrl+K**, not Ctrl+F, for search.
- **Three files**, single classic JS script (no ES modules), so `file://` works with
  no server.
- **Chrome/Edge only** — accepted limitation.
- Dirty/clean git state — **dropped** (would mean reimplementing `git status`).

## Explicitly Deferred (not in v1)

- Persisting the diff/selection across reloads.
- Copying whole directories (v1 copies single files only).
- Any drift-detection / multi-repo fan-out compare.
- In-browser file editing.
- A "rescan" scheduling story beyond a manual refresh.
