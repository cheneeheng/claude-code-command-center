---
artifact: ITER_03
status: ready
created: 2026-06-13
scope: Expand a card into its lazy file tree and select a file for each compare side
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02]
---

# ITER_03 — Drill In: File Tree & Selection

## §01 · Concept
> Unchanged — see SKELETON § 01

## §02 · Architecture

Implements `readTree(repo)` and introduces the **Selection** object.

- `readTree(repo)` → recursively enumerate the repo's directory handle into a `TreeNode`
  tree, **skipping any directory in the ignore-list**, populated lazily the first time a
  card is expanded and then memoised on the `Repo`.
- `Selection = { sideA, sideB }`, each `{ repoName, path, fileHandle }` or `null`. Lives
  at App level so it persists while the user moves around the board. Clicking a file
  fills the first empty side, or replaces side A then B in rotation (explicit UI shows
  which side a click will fill).

## §03 · Tech Stack
> Unchanged — see SKELETON § 03

## §05 · Frontend

### What this iteration builds
- **Expandable card:** clicking a `RepoCard` toggles a `FileTree` beneath it. First
  expand shows a spinner while `readTree` runs; result is cached so re-expanding is
  instant.
- **Tree rendering:** collapsible directories, clickable files. Ignored directories
  never appear.
- **Selection affordance:** each file row can be assigned to **Side A** or **Side B**
  (two small buttons, or click = fill-next with a visible "next: A/B" indicator). A
  persistent selection bar shows the current A and B (repo + path) with a clear/swap
  control. The selection bar is the bridge to ITER_04.

### Gotchas addressed
- **Large trees:** ignore-list applied during enumeration (not after), so `node_modules`
  etc. are never descended into — this is the main performance guard.
- **Deep trees:** directories render collapsed by default; children are read on the
  parent's first expand if not already loaded.
- **Stale handle mid-session:** if a tree read throws (folder changed underneath),
  surface a non-blocking notice and prompt a rescan rather than crashing.
