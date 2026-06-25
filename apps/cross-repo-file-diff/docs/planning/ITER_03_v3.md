---
artifact: ITER_03_v3
status: ready
created: 2026-06-14
scope: Render the real line-based diff in the slide-in right sidebar; the sidebar can only be open or minimized to a floating puck — there is no close/dismiss — and selection survives minimizing
sections_changed: [02, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON_v3, ITER_01_v3, ITER_02_v3]
---

# Vantage v3 — ITER_03: Diff Sidebar (open | minimized)

> §01 Concept — Unchanged — see SKELETON_v3 § 01
> §03 Tech Stack — Unchanged — see SKELETON_v3 § 03

---

## §02 · Architecture (changes only)

Brings **Compare** and **Sidebar** from stub to working. No new entities.

- **Compare.`diff(textA, textB)`** is invoked whenever `Selection.sideA` and
  `Selection.sideB` are both non-null. It reads both files via their stored handles
  (`getFile().text()`), runs the hand-written line-based LCS, and returns `DiffLine[]`
  where each line is `{ kind: 'add' | 'del' | 'same', text }`. No library, no CDN.
- **Binary guard:** if either file contains a NUL byte in the first ~8KB or fails UTF-8
  decode, skip diffing and render "binary file — can't compare."
- **Sidebar** owns `SidebarState.mode` — **`'open' | 'minimized'` only** (the v2
  `'closed'` mode does not exist in v3). View-only, never persisted. `mode` is only
  consulted once both sides are set; while fewer than two are selected, **neither panel
  nor puck renders** regardless of `mode`. Transitions:
  - fewer than two sides selected → nothing shown (panel and puck both absent).
  - both sides become selected → `mode = 'open'` (slide in) and diff renders.
  - minimize → `mode = 'minimized'`; floating puck shown; **selection untouched**.
  - puck click → `mode = 'open'`; the **same** selection re-renders.
  - picking a different file → selection changes, diff recomputes, `mode = 'open'`.
  - There is **no transition that hides both panel and puck** while a comparison exists —
    the comparison surface can never be dismissed once both sides are set.
- The last computed `DiffLine[]` is cached in memory keyed by the current A/B handle
  pair, so minimize→reopen does **not** re-read files or re-diff.

Key invariant: **minimize is presentation only.** `Selection` is the single source of
truth, mutated solely by file picks, so reopening always reflects the current A/B pair.

---

## §05 · Frontend (changes only)

### DiffView (stub → real)

`DiffView` renders the `DiffLine[]` as a flat, line-by-line coloured list using three
brand-token-driven classes — `.diff-add`, `.diff-del`, `.diff-same`. The sidebar header
shows the two sides (`repoA / path` vs `repoB / path`) so context is visible without
scrolling. **States:** identical files → "files are identical" rather than an empty diff;
binary → the binary notice from §02.

### Slide-in animation

The panel sits off-canvas (`transform: translateX(100%)`) and animates in via a CSS
`transform` transition driven by a class toggle keyed off `SidebarState.mode`. Animating
`transform` (not `width` / `right`) avoids per-frame layout reflow.

### Minimize control (no close)

- The sidebar header carries a **minimize** control and **no close/×**. Minimize sets
  `mode = 'minimized'`, slides the panel off-canvas, and reveals `FloatingPuck` — a small
  fixed-position button (brand accent) anchored to the right edge. Clicking the puck sets
  `mode = 'open'` and slides the panel back with the same diff. The compare-source
  highlights from ITER_02_v3 stay visible on the board throughout, so the user always
  knows which pair is loaded even while minimized.

### State wiring

A single `render()` reads `Selection` + `SidebarState` and reconciles the DOM: panel
position, puck visibility, diff contents, and the board highlight classes. No framework;
direct class toggles and the cached `lastDiff` array.

### Gotchas addressed

- **Binary files:** detected and refused before diffing, so the view never renders
  megabytes of binary as text.
- **No dismiss path:** there is exactly one way to hide the panel (minimize → puck) and
  one way back (puck → open); removing the close control removes the only state that
  could strand the user with a pending selection and no visible way to see it.
- **Reopen is instant:** cached `lastDiff` keyed by the A/B handle pair means
  minimize→reopen never touches the filesystem.
