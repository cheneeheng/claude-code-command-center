---
artifact: ITER_04_v3
status: ready
created: 2026-06-14
scope: Copy/overwrite a selected file from one repo onto the other behind an explicit confirm, and add an Open-in-VSCode button gated on a one-time optional root-path entry
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v3, ITER_01_v3, ITER_02_v3, ITER_03_v3]
mvp: true
mvp_target: >-
  A multi-file static Vantage (index.html + styles/* + scripts/*, classic scripts, no
  server, no build) that in Chrome/Edge points at a projects folder, shows every repo as
  a filterable/sortable board of cards, expands any card into its file tree, picks a file
  per side with the contributing repos highlighted, diffs the pair in a slide-in sidebar
  that can only be open or minimized to a floating puck (never closed), copies/overwrites
  one file onto the other behind an explicit confirm, and opens any repo in VSCode once a
  root path is set.
---

# Vantage v3 — ITER_04: Copy / Overwrite & Open in VSCode (MVP)

> §01 Concept — Unchanged — see SKELETON_v3 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v3 § 03

---

## §02 · Architecture (changes only)

Brings **Copy**, **Editor**, and the **Persist** root-path functions from stub to
working. No new in-memory entities; one persisted field gains a writer/reader.

### Copy

- `copyFile(srcFileHandle, dstDirHandle, name)` — read the source bytes
  (`srcFileHandle.getFile()`), then resolve the destination directory by walking the
  target repo's tree to the chosen file's parent (or repo root for a new file). Detect
  whether `name` already exists in the destination → drives the confirm. Write:
  `getFileHandle(name, { create: true })` → `createWritable()` → `write(contents)` →
  `close()`, where `contents` is the source file just read. Writes stay confined to the
  originally picked root.

### Editor + Persist root path

- **Persist.`saveRootPath(str)` / `loadRootPath() → string | null`** — store/read an
  optional absolute path for the projects root in IndexedDB, alongside the handle and
  cache (the stub reserved in ITER_01_v3).
- **Editor.`vscodeUri(repoName) → string | null`** — composes
  `vscode://file/<rootPath>/<repoName>`; returns `null` when `rootPath` is unset, which
  keeps the button disabled.

### Why a separate root-path entry exists (core constraint)

The File System Access API deliberately **does not expose the absolute path** of the
folder chosen via `showDirectoryPicker()` — the page gets an opaque handle plus the
folder `name`, never `/Users/.../projects`. So the VSCode link path **cannot be derived**
from the picked handle; it must be supplied separately. The folder picker (handle, no
path) and the root-path entry (path, no handle) are two different things by design — not
a gap to close. Resolution: a separate, optional, manual text field; Vantage works fully
without it, and only the VSCode buttons depend on it.

---

## §05 · Frontend (changes only)

### CopyBar in the sidebar

- The diff sidebar gains a **CopyBar**: `Copy A → B` and `Copy B → A`, each naming the
  exact target path that will be written.
- **Confirm-on-overwrite:** if the target exists, a modal states the full target path and
  that its contents will be replaced; the write proceeds only on explicit confirm.
  Copying to a path that doesn't exist yet creates it (shown for review, no destructive
  warning needed).
- **Post-write:** re-read the target and refresh the diff so the user immediately sees the
  files now match; show a brief success toast. (The sidebar is open during this — copy is
  only reachable when a comparison is loaded.)

### Root-path entry + Open in VSCode

- A small **Set root path** affordance in the brand header opens a text input where the
  user types/pastes the absolute projects-root path once (e.g. `/Users/eeheng/projects`);
  saved via `Persist.saveRootPath`, loaded on every subsequent open. Optional, labelled as
  needed only for opening repos in VSCode.
- On each **ExpandedCard**, the **Open in VSCode** button is **disabled** (tooltip "Set
  root path to enable") while `loadRootPath()` is null; once set, it becomes an anchor
  whose `href` is `Editor.vscodeUri(repo.name)`. Clicking hands the `vscode://` URL to the
  OS (VSCode registers the protocol handler); first click typically triggers a one-time
  browser prompt. No server, no shell-out — just an anchor.

### Build-time notes (address proactively)

- **Verify the `vscode://file/` path/slash format at build time** — it differs across OSes
  (notably Windows drive letters and leading slashes). Compose accordingly.
- `rootPath + "/" + repo.name` assumes repos are **direct children** of the root, which is
  Vantage's model. Nested repos would break it (out of scope below).

### Gotchas addressed

- **Destructive action isolation:** copy/overwrite is the only write path in the whole app
  and the only thing behind a confirm. No delete capability exists.
- **Write permission:** if the stored handle's permission has dropped to `'prompt'`, the
  copy action re-requests `readwrite` inside the click handler before writing.
- **Stale destination:** if the write throws (folder changed underneath), report it and
  prompt a rescan rather than leaving a half-written file ambiguous.

---

## Out of MVP scope

- Editor-agnostic open (Cursor `cursor://`, JetBrains, etc.) — VSCode hardcoded for now.
- Auto-deriving the root path from the picked handle — impossible per the FSA API; manual
  entry stands.
- Nested-repo support for VSCode path composition — model is direct children only.
- Syntax-highlighted or side-by-side (vs. flat line-by-line) diffs.
- A persistent sidebar shell **before** a comparison exists — v3 slides it in only once
  both sides are set.
- Persisting diff/selection across reloads; copying whole directories; undo /
  backup-on-overwrite; drift-detection / multi-repo fan-out; in-browser editing;
  scheduled rescan beyond the manual button.
- Offline-bundling brand fonts if the brand sheet references CDN assets.
