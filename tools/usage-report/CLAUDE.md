# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A CLI that prints a cross-session summary of Claude Code token usage and estimated cost — the
terminal counterpart to the `usage-dashboard` app. Both read the same data through the in-repo
`claude-usage` library.

## Commands

See README.md for full usage. Unlike the stdlib-only `tools/` scripts, this is a real installable
package (`[build-system]`, a `usage-report` console entry point, runtime dependency on
`claude-usage` as an editable path source), so `uv sync` before first use:

```
uv sync                       # creates .venv with claude-usage + dev tools
uv run usage-report --top 5
```

Lint/type-check with `uv run ruff check .` and `uv run mypy src`. Honours `$C4_CLAUDE_DIR`.

## Code structure (`src/usage_report/`)

- `cli.py` — argument parsing and the report rendering (the by-session / by-project / by-model
  tables). Reads data via `claude_usage.load_sessions`; computation that isn't presentation belongs
  in the library, not here.
- `__init__.py` — package surface / entry-point wiring.

## Invariants — do not break these

- **Parsing and pricing live in `claude-usage`, not here.** This CLI is a thin presenter over
  `load_sessions` / `estimated_cost`. Do not reimplement transcript parsing or the pricing table.
- **Cost is estimated, never billed** — token counts × list price. Keep the wording honest in
  output.
- The only runtime dependency is `claude-usage` (editable path source). Do not add others for a
  CLI formatting concern.

## Conventions

- Python member managed with `uv`; type hints everywhere; mypy `strict = true`; ruff (line length
  88). Never edit `uv.lock` by hand.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
