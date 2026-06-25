---
artifact: ITER_02
status: ready
created: 2026-06-13
scope: Filter and sort the board plus a Ctrl+K search overlay to find a repo fast
sections_changed: [05]
sections_unchanged: [01, 02, 03]
depends_on: [SKELETON, ITER_01]
---

# ITER_02 — Find: Filter, Sort & Search

## §01 · Concept
> Unchanged — see SKELETON § 01

## §02 · Architecture
> Unchanged — see SKELETON § 02 (all operations are client-side over the in-memory `Repo[]` from ITER_01)

## §03 · Tech Stack
> Unchanged — see SKELETON § 03

## §05 · Frontend

### What this iteration builds
- **Sort control** in the Toolbar: `last-activity` (default), `alphabetical`, `stack`.
  Sorting by stack groups cards under their primary stack badge; repos with no detected
  stack group under "Other".
- **Inline name filter:** a text input that live-filters visible cards by substring
  match on repo name (case-insensitive).
- **Ctrl+K search overlay (`SearchPalette`):** a keydown listener for
  Ctrl/Cmd+K calls `preventDefault()` and opens a centered overlay with a single input
  and a result list of matching repo names. Arrow keys move selection, Enter jumps to /
  highlights that card on the board and closes the overlay, Esc closes it. Chosen over
  Ctrl+F deliberately, to avoid overriding the browser's native find.

All filtering/sorting is pure in-memory transformation of the ITER_01 repo list — no
re-scan, no file reads.

### Gotchas addressed
- **Don't fight the browser:** only Ctrl/Cmd+**K** is intercepted; Ctrl+F is left to the
  browser. The overlay traps focus while open and restores it on close.
