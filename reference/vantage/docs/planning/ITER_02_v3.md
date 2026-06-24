---
artifact: ITER_02_v3
status: ready
created: 2026-06-14
scope: Expand a card into its lazy file tree, select a file per compare side, and reflect selection on the board via highlight states (compare-source A/B and active/expanded)
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v3, ITER_01_v3]
---

# Vantage v3 — ITER_02: Drill In, Select & Highlight

> §01 Concept — Unchanged — see SKELETON_v3 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v3 § 03

---

## §02 · Architecture (changes only)

Implements `Scanner.readTree(repo)`, introduces the **Selection** object, and defines
the **board highlight derivation**. No persisted entities added.

- `readTree(repo)` → recursively enumerate the repo's directory handle into a `TreeNode`
  tree, **skipping any ignore-listed directory during enumeration** (not after).
  Populated lazily on first expand, then memoised on the `Repo` (`fileTree`).
- `Selection = { sideA, sideB }`, each `{ repoName, path, handle }` or `null` (`repoName`
  is the repo's name string — the unique board key, since repos are direct children of the
  root). Lives at app level (on `Vantage.UI` state) so it survives moving around the
  board. Clicking a file fills the first empty side, or replaces A then B in rotation; the
  UI shows which side a click will fill.
- **Highlight derivation** (pure function of state, computed each render, nothing stored):
  - **compare-source** — `repo.name === Selection.sideA?.repoName` → `.is-compare-a`;
    `=== Selection.sideB?.repoName` → `.is-compare-b` (a repo can carry both).
  - **active** — the currently expanded card → `.is-active`.

### Resolved: what "selected repo" means

Per EeHeng's requirement 3, "the repo has been selected" is interpreted as the
**expanded/active card** (`.is-active`) — the repo you're currently drilling into — since
the model has no separate repo-pick action. "Repos where one or more files are selected
for comparison" maps to **compare-source** (`.is-compare-a/-b`). These are two distinct
treatments. If a dedicated repo-select gesture is wanted later, only the `.is-active`
trigger changes; the class and styling already exist.

---

## §05 · Frontend (changes only)

### Expandable card → file tree

- Clicking a `RepoCard` toggles a `FileTree` beneath it. First expand shows a spinner
  while `readTree` runs; the result is cached so re-expanding is instant.
- **Tree rendering:** collapsible directories, clickable files; ignored directories never
  appear. Directories render collapsed by default; children load on the parent's first
  expand if not already read.

### Selection affordance

- Each file row can be assigned to **Side A** or **Side B** (two small buttons, or
  click = fill-next with a visible "next: A / B" indicator). A persistent selection bar
  shows current A and B (repo + path) with a clear/swap control. This bar is the bridge
  to the diff sidebar (ITER_03_v3).

### Board highlights (requirement 3, wired)

- Cards now apply the derived classes every render: a **compare-source** card shows a
  small **A** or **B** badge (or both) so it's obvious which side a repo feeds; the
  **active/expanded** card carries its own distinct treatment. Both are styled from the
  skeleton's reserved classes — no new persisted state.

### Gotchas addressed

- **Large trees:** ignore-list applied *during* enumeration, so `node_modules` etc. are
  never descended — the main performance guard.
- **Stale handle mid-session:** if a tree read throws (folder changed underneath),
  surface a non-blocking notice and prompt a rescan rather than crashing.
- **Highlight = derived:** classes are recomputed from `Selection` + active card on each
  render, so they can never drift out of sync with the actual selection.
