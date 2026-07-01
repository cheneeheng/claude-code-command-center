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

This is the whole design; README.md has the full diagrams. Every number comes from one of two
independent sources:

- **Source 1 — session transcripts** (`~/.claude/projects/**/*.jsonl`, written by Claude Code):
  `session_stats.py` loads per-session token counts from `claude-usage` and aggregates them
  (`summarize_sessions`). Cost is **estimated** (tokens × pricing table). All sessions, full history.
- **Source 2 — statusline logs** (`~/.claude/statusline/**/*.jsonl`, written by the optional
  `statusline-hook` tool): `live_statusline.py` reads live per-session state (5h/7d rate limits,
  context %, model name, **actual** cost). Recent live sessions only.
- `merge.py` reconciles them into the `/api/data` payload; `dashboard_server.py` is HTTP transport
  only; `dashboard.html` plus the split `css/` and `js/` sources render the payload and compute
  nothing. `dashboard_config.py` holds runtime config only (the pricing table lives in
  `claude-usage`).

The browser CSS and JS are split into small single-concern files under `css/` and `js/`;
`dashboard_server.py` concatenates each in a fixed order (see `_CSS_PARTS` / `_JS_PARTS`) into the
one `/dashboard.css` and `/dashboard.js` responses. The JS parts are plain (non-module) scripts
sharing one global scope, so `js/app.js` (the bootstrap) must stay last in that list.

## Invariants — do not break these

- **Actual cost wins when available, and only for live sessions.** The override lives in
  `merge.py._apply_actual_cost` and nowhere else. Historical sessions keep the estimate. Do not
  scatter cost-override logic elsewhere.
- **The cost-by-model breakdown is always the estimate** — the statusline does not attribute cost
  per model. Do not try to overlay actual cost there.
- **All computation is server-side.** The `js/` browser code is pure display. New aggregate stats
  go in `session_stats.summarize_sessions`; new live fields in `live_statusline`; then render. Never
  move computation into the browser.
- **The payload contract `{stats, sessions, live}` couples server and the `js/` render code** —
  change both ends together.
- **Pricing is not owned here.** New model / new price → edit `claude_usage.MODEL_COSTS` (and
  `model_family` if needed); keep `js/models.js` (`modelFamily`, `MODEL_SHADES`, `modelShort`) in
  step. If estimated and actual diverge, the pricing table is stale — not a parsing bug.
- The statusline export is optional; the dashboard reads it if present and shows "Hook not set up"
  if not. Do not make it a hard dependency.

## Conventions

- Python member managed with `uv`; only runtime dependency is the in-repo `claude-usage` library.
  ruff (line length 88) and mypy `strict = true`.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
