# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A decision-focused dashboard over Claude Code usage: projection, spend breakdown, and skill and
tool health. It replaces `apps/usage-dashboard`. The build plan is
`product/plans/usage-insights.md`. Its Design section is binding.

## Commands

Managed with `uv`. `uv sync` first, then:

```
uv run usage-insights export          # copy new/changed transcripts into the store
uv run usage-insights --no-open       # export, then serve on 127.0.0.1:8090
uv run pytest                         # tests (fixture tree in tests/fixtures/claude)
uv run ruff check . && uv run mypy src
```

Frontend, from `web/` with Bun: `bun run typecheck`, `bun run test`, `bun run build` (writes the
git-ignored `src/usage_insights/static/`), `bun run dev` (Vite, proxying `/api` to :8090).

Install: `scripts/usage-insights-setup.ps1 -Action install|uninstall` (Windows, also registers
the `\ClaudeAutomation\usage-insights\export` task) and `scripts/usage-insights-setup.sh
install|uninstall` (prints a cron line). `setup/registry.ps1` delegates to the PowerShell script
and detects the install by that task, so a change to the script's parameters or task name must
update `setup/` in the same change.

Env: `C4_CLAUDE_DIR` (Claude config dirs, via `claude-usage`), `C4_USAGE_INSIGHTS_HOME` (store
dir, default `~/.usage-insights`). Point both at temp dirs in any check that runs the CLI, so it
never writes to the real store.

## Code structure (`src/usage_insights/`)

- `cli.py` — argument parsing, the export-then-serve flow, and exit codes.
- `export.py` — incremental export: re-parses only files whose size or mtime changed.
- `store.py` — the SQLite schema, its version handling, and the write lock.
- `inventory.py` — installed skills, agents, MCP servers, and built-in tools.
- `aggregate.py` — the `/api/summary` payload: projection, spend, and health. Tunable numbers are
  named constants at its top.
- `server.py` — the HTTP API, the Host check, and the static frontend.

`web/src/catalogue/` holds one presentational component per file, no data fetching.
`web/src/layout/defaultLayout.ts` maps the payload to panels as data, so the later AG-UI phase can
replace the layout at runtime. Keep it data, not JSX.

## Invariants — do not break these

- **Parsing and pricing live in `claude-usage`.** This app stores and aggregates; it never parses
  transcripts itself.
- **The store is upsert-only.** Rows are never deleted, so history outlives Claude Code's
  transcript cleanup. A message keeps the `session_id` it was first stored with, and a copy with
  fewer output tokens (a fork's mid-stream snapshot) never replaces it. A folded subagent file
  never blanks a session's `title` or `cwd`.
- **The server only reads the store** (`store.connect_read_only`, `mode=ro`); only an export
  writes. `POST /api/refresh` rejects cross-site requests, on top of the Host check.
- **Cost is computed at query time** from `claude_usage.price_for`, never stored, so a price fix
  needs no re-export.
- **One writer at a time.** An export takes `BEGIN IMMEDIATE` with a short timeout and raises
  `ExportBusy` instead of waiting out a long first export. A store backup must happen before the
  write lock is taken.
- A schema change bumps `store.SCHEMA_VERSION`. The exporter then backs up the old store and
  rebuilds from the transcripts still on disk, which loses rows for deleted transcripts. Avoid it
  when an additive change will do.

## Conventions

- Python member managed with `uv`; mypy `strict = true`; ruff (line length 88).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
