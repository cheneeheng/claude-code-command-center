# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A decision-focused dashboard over Claude Code usage: projection, spend breakdown, and skill and
tool health, plus a chat whose agent adds panels. It replaced the retired `usage-dashboard`. The build
plans are `product/plans/usage-insights.md` and `product/plans/ag-ui-dashboard.md` (the chat,
query, layout, and reference data). Their Design sections are binding.

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
dir, default `~/.usage-insights`), `C4_USAGE_INSIGHTS_API_KEY` (the chat's Anthropic key; unset
turns the chat off), `C4_USAGE_INSIGHTS_MODEL` (default `claude-sonnet-5-5`). Point the first two at
temp dirs in any check that runs the CLI, so it never writes to the real store. On Windows give
`C4_USAGE_INSIGHTS_HOME` a Windows path: a Git Bash `/c/...` path reaches Python as `C:\c\...`.
A run with a real key spends API credit: ask first.

## Code structure (`src/usage_insights/`)

- `cli.py` — argument parsing, the export-then-serve flow, and exit codes.
- `export.py` — incremental export: re-parses only files whose size or mtime changed.
- `store.py` — the SQLite schema, its version handling, and the write lock.
- `inventory.py` — installed skills, agents, MCP servers, and built-in tools.
- `aggregate.py` — the `/api/summary` payload: projection, spend, and health. Tunable numbers are
  named constants at its top. Its row helpers (`message_cost`, `local_day`, `project_labels`,
  `session_project`, `range_start`) are shared with `query.py`, so the two never disagree.
- `query.py` — the typed query behind `POST /api/query` and the agent's `run_query`: `parse`
  validates a spec once (a `ValueError` naming the field), `run` computes it read-only.
- `reference.py` — `reference.json`: prices from LiteLLM, built-in tools from the docs, built-in
  agents from the `claude` CLI's `initialize`, each at most daily, each with a fallback. Only the
  `export` subcommand calls `refresh`; tests block its `urlopen` and `run` (`tests/conftest.py`).
- `agent.py` — the chat: a sync port of the `ceh-ag-ui` agent-server loop, streaming AG-UI events.
  Append-only transcript per thread, frontend tools allowlisted, two read-only backend tools.
- `server.py` — the HTTP API, the Host check, the static frontend, `/api/layout`, and the SSE
  response for `/api/agent`.

`web/src/catalogue/` holds one presentational component per file, no data fetching, plus
`define.ts` and `kinds.tsx` (the five generated panel kinds and their zod schemas, which refuse
style-like keys). `web/src/layout/defaultLayout.ts` maps the payload to panels as data; keep it
data, not JSX. `layout/model.ts` turns it into the saved shape (refs plus generated panels) and
back; `layout/edits.ts` holds the agent's four edits; `hooks/useAgent.ts` drives the chat.

## Invariants — do not break these

- **Parsing and pricing live in `claude-usage`.** This app stores and aggregates; it never parses
  transcripts itself.
- **The store is upsert-only.** Rows are never deleted, so history outlives Claude Code's
  transcript cleanup. A message keeps the `session_id` it was first stored with, and a copy with
  fewer output tokens (a fork's mid-stream snapshot) never replaces it. A folded subagent file
  never blanks a session's `title` or `cwd`.
- **The server only reads the store** (`store.connect_read_only`, `mode=ro`); only an export
  writes `usage.db`. Request handlers write `layout.json` and nothing else, apart from the export
  `/api/refresh` runs. The `export` subcommand writes `usage.db` and `reference.json`. Every POST,
  PUT, and DELETE rejects cross-site requests, on top of the Host check.
- **Cost is computed at query time** from `claude_usage.price_for` with the fetched prices as the
  overlay, never stored, so a price fix needs no re-export.
- **The agent never writes a figure.** A generated panel holds a typed query that the server
  runs; there is no free-form SQL tool. The browser never writes the prompt: client system,
  developer, and assistant messages are ignored, and frontend tools outside `FRONTEND_TOOLS` are
  dropped.
- **The chat key is `C4_USAGE_INSIGHTS_API_KEY`, never `ANTHROPIC_API_KEY`**, which Claude Code
  reads too. The `initialize` call strips both from the child's env.
- **One writer at a time.** An export takes `BEGIN IMMEDIATE` with a short timeout and raises
  `ExportBusy` instead of waiting out a long first export. A store backup must happen before the
  write lock is taken.
- A schema change bumps `store.SCHEMA_VERSION`. The exporter then backs up the old store and
  rebuilds from the transcripts still on disk, which loses rows for deleted transcripts. Avoid it
  when an additive change will do.

## Conventions

- Python member managed with `uv`; mypy `strict = true`; ruff (line length 88).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
