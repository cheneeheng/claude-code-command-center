# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An HTTP server that reads Claude Code's local logs and serves a single-page dashboard of token
usage, cost, and live rate limits. Its one dependency is the in-repo `claude-usage` library
(transcript parsing + pricing).

## Running

See README.md for full usage and the data-flow diagrams. Quick start:
`uv run python usage-dashboard.py` (default `localhost:8080`; `--host`/`--port`/`--claude-dir`).
Env: `C4_CLAUDE_DIR` (config dirs, `os.pathsep`-separated), `C4_STATUSLINE_LIVE_TIMEOUT` (live
idle seconds, default 1800). For a quick sanity check, parse/type-check the changed file
(`uv run python -m py_compile <file>`).

## Architecture — two data sources, one reconciler

This is the whole design; README.md has the full diagrams. Folder layout: `usage-dashboard.py`
(entry) at root; the Python modules in `backend/`; the UI in `web/` (`dashboard.html` + `css/` +
`js/`); the Windows Task Scheduler helpers in `scripts/`. The entry puts `backend/` on `sys.path`,
so the backend modules keep their flat imports of each other. Every number comes from one of two
independent sources:

- **Source 1 — session transcripts** (`~/.claude/projects/**/*.jsonl`, written by Claude Code):
  `backend/session_stats.py` loads sessions + the `Activity` rollup from `claude-usage` (via a
  memoized parse cache), scopes them to the request's `range`/`project`, and aggregates them
  (`summarize_sessions`) — totals, deltas, plan value, breakdowns, activity series, per-session
  economics. Cost is **estimated** (tokens × pricing table). All sessions, full history.
- **Source 2 — statusline logs** (`~/.claude/statusline/**/*.jsonl`, written by the optional
  `statusline-hook` tool): `backend/live_statusline.py` reads live per-session state (5h/7d rate
  limits, context %, model name, informational actual cost), plus rate-limit `history` and a cap-ETA
  `forecast`. Recent live sessions only.
- `backend/merge.py` assembles the `/api/data` payload; `backend/report.py` renders `/api/report.md`;
  `backend/dashboard_server.py` is HTTP transport only (`/api/data`, the cheap `/api/live` fast-poll,
  `/api/export.csv`, `/api/report.md`); `web/dashboard.html` plus the split `web/css/` and `web/js/`
  sources render the payload and compute nothing (bar client-side display filtering — see invariants).
  `backend/dashboard_config.py` holds runtime config only (the pricing table lives in `claude-usage`).

The browser CSS and JS are split into small single-concern files under `web/css/` and `web/js/`;
`backend/dashboard_server.py` concatenates each in a fixed order (see `_CSS_PARTS` / `_JS_PARTS`)
into the one `/dashboard.css` and `/dashboard.js` responses. The JS parts are plain (non-module)
scripts sharing one global scope, so `web/js/app.js` (the bootstrap) must stay last in that list.

## Invariants — do not break these

- **The pricing-table estimate is canonical.** Every aggregate and every session-row cost is the
  estimate; there is no actual-cost overlay (the former `merge.py._apply_actual_cost` was removed in
  v4). The statusline's actual per-session cost is informational only — it appears in the live
  rate-limit card (`live.sessions[].session_cost`) and is never merged into `stats` or `sessions`.
- **All computation is server-side.** The `js/` browser code is pure display, with one sanctioned
  exception: client-side *display filtering* of already-loaded rows (model/day/search chips) that
  never recomputes an aggregate. New aggregate stats go in `session_stats.summarize_sessions`; new
  live fields in `live_statusline`; then render. Never move aggregation into the browser.
- **`/api/data` is scoped by `range` and `project`.** `range` ∈ `7d,30d,90d,12m,all` (default `all`);
  `project` is an exact-match filter. Cards, tables, and deltas are session-scoped; the `Activity`
  time-series (`by_day`/`heatmap`/`model_mix`/`hour_dow`/`tools`) are project-agnostic by design.
- **The payload contract `{stats, sessions, live}` couples server and the `js/` render code** —
  change both ends together. A new payload key appears only in the iteration that renders it.
- **Pricing is not owned here.** New model / new price → edit `claude_usage.MODEL_COSTS` (and
  `model_family` if needed); keep `web/js/models.js` (`modelFamily`, `MODEL_SHADES`, `modelShort`) in
  step.
- The statusline export is optional; the dashboard reads it if present and shows "Hook not set up"
  if not. Do not make it a hard dependency.

## Conventions

- Python member managed with `uv`; only runtime dependency is the in-repo `claude-usage` library.
  ruff (line length 88) and mypy `strict = true`.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
