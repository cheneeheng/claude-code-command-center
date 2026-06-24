---
artifact: ITER_01
status: ready
created: 2026-06-13
scope: Real folder access, repo scan with metadata, board of cards, and IndexedDB persistence
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON]
---

# ITER_01 — Folder Access, Scan & Board

## §01 · Concept
> Unchanged — see SKELETON § 01

## §02 · Architecture

Implements the **Scanner** and **Persist** modules and wires the **Board UI** to real
data (skeleton rendered placeholder cards).

- `chooseRoot()` → calls `showDirectoryPicker({ mode: 'readwrite', id: 'vantage-root' })`,
  stores the returned handle via Persist, then triggers a scan.
- `scanRoot(dirHandle)` → iterate `dirHandle.values()`, keep entries where `kind === 'dir'`;
  each becomes a `Repo`. For each repo gather `detectStack()` and `lastActivity()` **in
  parallel** (`Promise.all` over repos), never sequentially. Write the resulting
  `Repo[]` (minus live handles) to the scan cache.
- Persist (IndexedDB, store `vantage`): `saveHandle` / `loadHandle` for the directory
  handle; `saveCache` / `loadCache` for `{ scannedAt, repos: [{name, stack, lastActivity}] }`.

`Repo` fields populated this iteration: `name`, `dirHandle`, `stack[]`, `lastActivity`.
`fileTree` stays unpopulated until ITER_03.

## §03 · Tech Stack
> Unchanged — see SKELETON § 03

## §05 · Frontend

### What this iteration builds
- **Empty state → board.** Before a folder is chosen, show the "Choose folder" prompt.
  After choosing, render one `RepoCard` per repo: name, stack badge(s), and a
  human-relative last-activity ("3d ago"). Default order: most-recent-activity first.
- **Reopen flow.** On load, `loadHandle()`; if present, call `handle.queryPermission({ mode: 'readwrite' })`.
  If `'granted'`, render straight from cache. If `'prompt'`, show a single "Reconnect folder"
  button — **`requestPermission` must run inside that click handler** (a user gesture), not on load.
- **Rescan.** A manual "Rescan" button re-runs `scanRoot` and refreshes the cache.

### `lastActivity(repoHandle)` — fallback chain
1. `lastModified` of `.git/logs/HEAD`.
2. else `lastModified` of `.git/HEAD`.
3. else shallow ignore-listed walk, newest file mtime (depth-capped).
Return epoch ms, or `null` → card shows "—" and sorts last.

Ignore-list (shared): `.git`, `node_modules`, `venv`, `.venv`, `target`, `dist`,
`build`, `.next`, `__pycache__`.

### `detectStack(repoHandle)`
Probe root for marker files → badges: `pyproject.toml`/`requirements.txt` → Python,
`package.json` → Node, `Cargo.toml` → Rust, `go.mod` → Go, `pom.xml`/`build.gradle` → JVM.

### Gotchas addressed
- **Stale handle:** a stored handle whose folder was moved/deleted throws on use — catch,
  drop the cached handle, fall back to empty state.
- **Parallel reads:** gather per-repo metadata with `Promise.all`, not awaited in a loop.
