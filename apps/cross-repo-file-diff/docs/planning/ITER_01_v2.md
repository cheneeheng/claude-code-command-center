---
artifact: ITER_01_v2
status: ready
created: 2026-06-14
scope: Wire the hand-rolled diff into the slide-in right sidebar; close hides and minimize collapses to a floating puck, both preserving the file selection
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v2]
---

# Vantage v2 — ITER_01: Slide-in Diff Sidebar

> §01 Concept — Unchanged — see SKELETON_v2 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v2 § 03

---

## §02 · Architecture (changes only)

This iteration adds no new entities or modules; it brings the **Compare** and
**Sidebar** modules from stub to working, and makes their relationship explicit.

- **Compare.`diff(textA, textB)`** is now invoked whenever `Selection.sideA` and
  `Selection.sideB` are both non-null. It reads both files via their stored handles
  (`getFile().text()`), runs the line-based diff, and returns `DiffLine[]` where each
  line is `{ kind: 'add' | 'del' | 'same', text }`.
- **Sidebar** owns `SidebarState.mode` (`'open' | 'closed' | 'minimized'`) — a
  **view-only** value, never written to IndexedDB. State transitions:
  - both sides become selected → `mode = 'open'` (slide in) and diff renders.
  - close (×) → `mode = 'closed'`; selection untouched; no puck shown.
  - minimize → `mode = 'minimized'`; floating puck shown; selection untouched.
  - puck click → `mode = 'open'`; the **same** selection re-renders (no recompute
    needed beyond reading state; cache the last `DiffLine[]` so reopen is instant).
  - picking a different file → selection changes, diff recomputes, `mode = 'open'`.

Key invariant: **close and minimize are presentation only.** `Selection` is the single
source of truth and is mutated solely by file picks, so reopening always reflects the
current A/B pair.

---

## §05 · Frontend (changes only)

### DiffView (stub → real)

`DiffView` now renders the `DiffLine[]` as a flat, line-by-line coloured list using three
brand-token-driven classes — `.diff-add`, `.diff-del`, `.diff-same`. Header of the
sidebar shows the two sides being compared (`repoA / path` vs `repoB / path`) so the
context is visible without scrolling.

### Slide-in animation

The panel is positioned off-canvas (`transform: translateX(100%)`) and animated in with a
CSS `transform` transition driven by a class toggle keyed off `SidebarState.mode`.
Animating `transform` (not `width`/`right`) avoids layout reflow jank on each frame.

### Close / minimize controls

- **Close (×):** sets `mode = 'closed'`, slides the panel off-canvas. The selection
  badges (which file is A, which is B) remain visible on the board/cards so the user
  knows a comparison is still pending.
- **Minimize:** sets `mode = 'minimized'`, slides the panel off-canvas, and reveals
  `FloatingPuck` — a small fixed-position button (brand accent) anchored to the right
  edge. Clicking it sets `mode = 'open'` and slides the panel back with the same diff.

### State wiring

- A single `render()` reads `Selection` + `SidebarState` and reconciles the DOM: panel
  position, puck visibility, and diff contents. No framework; direct class toggles and a
  cached `lastDiff` array.
- The last computed `DiffLine[]` is held in memory keyed by the current A/B handle pair,
  so close→reopen and minimize→reopen do **not** re-read files or re-diff.

### How to run locally

Unchanged — open `index.html` in Chrome/Edge. To exercise: pick a file in two repos →
sidebar slides in with the diff → test ×, minimize, and puck-reopen; confirm the A/B
selection survives all three.
