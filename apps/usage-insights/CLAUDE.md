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
uv run pytest                         # tests (fixture tree in tests/fixtures/claude)
uv run ruff check . && uv run mypy src
```

Env: `C4_CLAUDE_DIR` (Claude config dirs, via `claude-usage`), `C4_USAGE_INSIGHTS_HOME` (store
dir, default `~/.usage-insights`). Point both at temp dirs in any check that runs the CLI, so it
never writes to the real store.

## Code structure (`src/usage_insights/`)

- `cli.py` — argument parsing and exit codes.
- `export.py` — incremental export: re-parses only files whose size or mtime changed.
- `store.py` — the SQLite schema, its version handling, and the write lock.

## Invariants — do not break these

- **Parsing and pricing live in `claude-usage`.** This app stores and aggregates; it never parses
  transcripts itself.
- **The store is upsert-only.** Rows are never deleted, so history outlives Claude Code's
  transcript cleanup. A message keeps the `session_id` it was first stored with. A folded subagent
  file never blanks a session's `title` or `cwd`.
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
