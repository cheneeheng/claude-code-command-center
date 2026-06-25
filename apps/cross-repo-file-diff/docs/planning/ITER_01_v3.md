---
artifact: ITER_01_v3
status: ready
created: 2026-06-14
scope: Wire the multi-file scaffold for real (namespace + load order) and stand up a live board — Persist + Scanner produce real repo cards with stack badges and relative activity, plus filter and sort
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v3]
---

# Vantage v3 — ITER_01: Multi-file Wiring & Live Board

> §01 Concept — Unchanged — see SKELETON_v3 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v3 § 03

---

## §02 · Architecture (changes only)

Brings the **Persist** and **Scanner** modules from stub to working, and makes the
multi-file wiring real. No new entities; `Repo` gets its fields populated.

### Namespace + load order (stub → contract)

- `namespace.js` defines `window.Vantage = window.Vantage || {}` and loads **first**.
- Each module file attaches one object: `Vantage.Persist`, `Vantage.Scanner`, etc.
- `app.js` loads **last** and is the only file that touches the DOM on boot.
- A module that calls another must appear **after** it in `index.html`'s `<script>`
  order (e.g. `scanner.js` after `persist.js`; `app.js` after both). This ordering is
  the dependency contract that replaces `import`/`export`.

### Persist (IndexedDB, store `vantage`)

- `saveHandle(handle)` / `loadHandle() → handle | null` — the root directory handle.
- `saveCache(cache)` / `loadCache() → cache | null` where
  `cache = { scannedAt, repos: [{ name, stack, lastActivity }] }` (live handles are
  **not** serialised).
- `saveRootPath` / `loadRootPath` exist as stubs here; wired in ITER_04_v3.

### Scanner

- `chooseRoot()` → `showDirectoryPicker({ mode: 'readwrite', id: 'vantage-root' })`,
  store the handle via Persist, then `scanRoot`.
- `scanRoot(dirHandle)` → iterate `dirHandle.values()`, keep `kind === 'directory'`
  entries; each becomes a `Repo`. Gather `detectStack()` and `lastActivity()` for every
  repo **in parallel** (`Promise.all` over repos, never awaited in a loop). Write the
  resulting `Repo[]` (minus live handles) to the scan cache.
- `lastActivity(repoHandle)` → fallback chain: (1) `lastModified` of `.git/logs/HEAD`;
  (2) else `.git/HEAD`; (3) else shallow ignore-listed walk, newest file mtime
  (depth-capped). Returns epoch ms, or `null` → card shows "—" and sorts last.
- `detectStack(repoHandle)` → probe root markers → badges: `pyproject.toml` /
  `requirements.txt` → Python, `package.json` → Node, `Cargo.toml` → Rust, `go.mod` →
  Go, `pom.xml` / `build.gradle` → JVM. Multiple badges allowed.

Shared **ignore-list**: `.git`, `node_modules`, `venv`, `.venv`, `target`, `dist`,
`build`, `.next`, `__pycache__`.

`Repo` fields populated this iteration: `name`, `dirHandle`, `stack[]`, `lastActivity`.
`fileTree` stays unpopulated until ITER_02_v3.

---

## §05 · Frontend (changes only)

### Board comes alive

- **Empty state → board.** Before a folder is chosen, show the **Change folder** prompt.
  After choosing, render one `RepoCard` per repo: name, stack badge(s), and a
  human-relative last-activity ("3d ago"). Default order: most-recent-activity first.
- **Reopen flow.** On load, `loadHandle()`; if present, call
  `handle.queryPermission({ mode: 'readwrite' })`. If `'granted'`, render straight from
  cache. If `'prompt'`, show a single **Reconnect folder** button — `requestPermission`
  **must run inside that click handler** (a user gesture), not on load.
- **Filter + sort.** The header **board filter** live-filters visible cards by
  case-insensitive substring on repo name. A sort control offers `last-activity`
  (default), `alphabetical`, `stack` (groups under primary badge; no-stack repos under
  "Other"). All pure in-memory transforms of the `Repo[]` — no re-scan, no file reads.
- **Rescan.** A manual **Rescan** button re-runs `scanRoot` and refreshes the cache.

The highlight CSS classes from the skeleton stay inert this iteration (no `Selection`
exists yet); they get wired in ITER_02_v3.

### Gotchas addressed

- **`file://` stays classic.** All new code ships as classic scripts on `window.Vantage`;
  no `import`/`export` creeps in, or double-click stops working.
- **Load order:** `app.js` last, leaf modules after their dependencies — a misorder
  throws `Vantage.X is undefined` at boot.
- **Stale handle:** a stored handle whose folder was moved/deleted throws on use — catch,
  drop the cached handle, fall back to the empty state.
- **Parallel reads:** per-repo metadata via `Promise.all`, not awaited in a loop, so a
  100-repo folder scans concurrently.
