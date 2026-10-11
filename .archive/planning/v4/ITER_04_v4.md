---
artifact: ITER_04_v4
status: ready
created: 2026-07-03
scope: interactivity — drill-down navigation (project/model/day), session search, project filter, URL-encoded view state
sections_changed: [02, 05]
sections_unchanged: [01, 03, 04]
depends_on: [SKELETON_v4, ITER_02_v4, ITER_03_v4]
---

# ITER_04_v4 — drill-down, filters, shareable state

Frontend-only iteration. The server already accepts `project=` (ITER_02); everything
else here is display-state — allowed client-side under the "computation server-side"
invariant because it filters *which loaded rows are shown*, never recomputes aggregates.

## §01 · Concept

> Unchanged — see SKELETON_v4 § 01.

## §02 · Architecture

View-state model (single source of truth in `settings.js`, mirrored to the URL):

| Key | Scope | Effect |
|---|---|---|
| `range` | server | `/api/data?range=` (ITER_03) |
| `project` | server | `/api/data?project=` — all cards + table rescope |
| `model` | client | session-table display filter |
| `day` | client | session-table display filter (`last_ts` on that local day) |
| `q` | client | search over session id + project name |
| `sort`,`dir`,`page` | client | existing table state, now URL-mirrored |

URL is the shareable form: `history.replaceState` writes
`?range=30d&project=X&model=Y&day=2026-07-01&q=&sort=cost_usd&dir=desc&page=2`
(empty keys omitted). On load, URL params win over localStorage; localStorage keeps
only `range`, page size, theme, timeout (device prefs), not the drill-down state.

## §03 · Tech Stack

> Unchanged — see SKELETON_v4 § 03.

## §04 · Backend

> Unchanged — see ITER_02_v4 § 04. (No new endpoints or params.)

## §05 · Frontend

**Drill-down wiring (render.js):**
- Top Projects rows and session-table project cells → `<button class="link">` setting
  `project` (server refetch). Active filter renders as a dismissible chip next to the
  range selector: `project: multi-repo-plan-runner ✕`.
- Usage-by-Model / Cost-by-Model rows, model tags, and model-mix legend → set `model`
  (client filter chip, same pattern).
- Daily chart bars and heatmap cells → click sets `day` (client filter chip). Extend
  `makeBarChart` with an optional `onBarClick(d)`; heatmap cells become `<button>`s
  (keyboard-reachable — mouse-only canvas clicks get a keyboard path via the heatmap,
  which covers the same days).
- Expensive-sessions rows → set `q` to the session id (jumps the table to it).

**Search (settings.js + render.js):** debounced (250ms) text input in the session-table
header row; case-insensitive substring match on `session_id` and `project`; count badge
reflects matches; resets `page` to 1.

**Filter pipeline in render.js** (order matters, applied to the loaded `sessions`):
lookback-days (existing) → `model` → `day` → `q` → sort → paginate. Each chip removal
re-renders from `lastData`; `project`/`range` changes refetch instead.

**URL state (settings.js):** `readStateFromURL()` at boot (before first fetch);
`writeStateToURL()` after every state mutation via `history.replaceState` (no history
spam). Table sort/page hooks (`onSortChange`, `onPageChange`) call it too.

**Accessibility:** chips are `<button>`s with `aria-label="remove filter …"`; every
click target introduced here is reachable by keyboard; filter state is announced by the
visible chips + match count, not color.

**Validation:** deep-link a full URL into a fresh tab and confirm identical view;
back/forward not required (replaceState by design); empty-result state renders the
existing "no sessions" empty block with chips still visible for escape.
