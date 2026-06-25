---
artifact: ITER_04
status: ready
created: 2026-06-13
scope: Read both selected files and render a line-based diff between them
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03]
---

# ITER_04 — Compare: Diff View

## §01 · Concept
> Unchanged — see SKELETON § 01

## §02 · Architecture

Implements the **Compare** module: `diff(textA, textB) → DiffLine[]`.

- Read both sides' contents via `fileHandle.getFile().then(f => f.text())`.
- `diff()` is a hand-written line-based LCS producing a list of
  `{ type: 'equal'|'add'|'del', a?, b?, text }` rows. No external library, no CDN.
- A `binary?` guard: if either file looks binary (contains a NUL byte in the first ~8KB,
  or fails UTF-8 decode), skip diffing and report "binary file — can't compare."

## §03 · Tech Stack
> Unchanged — see SKELETON § 03

## §05 · Frontend

### What this iteration builds
- **ComparePanel → DiffView.** Once both selection sides are set, the panel reads both
  files and renders the diff: two-column (A | B) or unified line view, with added/removed
  lines color-coded and equal lines shown for context. Header shows
  `repoA/path` vs `repoB/path`.
- **States:** empty (fewer than two sides selected) → prompt to pick files;
  identical files → "files are identical" rather than an empty diff;
  binary → the binary notice from §02.
- This iteration is **read-only** — no write button is rendered yet. (The copy action
  arrives in ITER_05; until then no copy control exists, per the "omit the control until
  its iteration" convention.)

### Gotchas addressed
- **Binary files:** detected and refused before diffing, so the view never tries to
  render megabytes of binary as text.
- **Large text files:** diff runs on demand (when both sides are set), not eagerly on
  selection.
