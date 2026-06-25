---
artifact: ITER_05
status: ready
created: 2026-06-13
scope: Copy/overwrite a selected file from one repo onto the other, behind an explicit confirm
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04]
mvp: true
mvp_target: >-
  A single static page (index.html + vantage.css + vantage.js) that, in Chrome/Edge,
  lets you point at a projects folder, survey every repo as a filterable/sortable board
  of cards (Ctrl+K to find), expand any card into its file tree, diff a file from two
  repos, and copy/overwrite one onto the other with explicit confirmation.
---

# ITER_05 — Copy / Overwrite (MVP)

## §01 · Concept
> Unchanged — see SKELETON § 01

## §02 · Architecture

Implements the **Copy** module: `copyFile(srcFileHandle, dstDirHandle, name)`.

- Resolve the destination directory handle by walking the target repo's tree to the
  chosen file's parent (or the repo root for a new file).
- Detect whether `name` already exists in the destination → drives the confirm copy.
- Write: `getFileHandle(name, { create: true })` → `createWritable()` → `write(contents)`
  → `close()`. Writes are confined to the originally picked root.

## §03 · Tech Stack
> Unchanged — see SKELETON § 03

## §05 · Frontend

### What this iteration builds
- **CopyBar** in the ComparePanel: `Copy A → B` and `Copy B → A`. The direction names
  the exact target path that will be written.
- **Confirm-on-overwrite:** if the target already exists, a modal states the full target
  path and that its contents will be replaced; the write proceeds only on explicit
  confirm. Copying to a path that doesn't exist yet creates it (still shown for review,
  no destructive warning needed).
- **Post-write:** re-read the target and refresh the diff so the user immediately sees
  the files now match. Show a brief success toast.

### Gotchas addressed
- **Destructive action isolation:** copy/overwrite is the only write path in the whole
  app and the only thing behind a confirm. No delete capability exists in the MVP.
- **Write permission:** if the stored handle's permission has dropped to `'prompt'`, the
  copy action re-requests `readwrite` inside the click handler before writing.
- **Stale destination:** if the write throws (folder changed underneath), report it and
  prompt a rescan rather than leaving a half-written file ambiguous.

## Out of MVP scope
- Copying whole directories (MVP copies single files only).
- Undo / backup-on-overwrite safety net.
- Drift-detection or multi-repo fan-out compare.
- In-browser file editing.
- Persisting diff/selection across reloads.
- Scheduled / automatic rescan beyond the manual button.
