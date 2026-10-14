# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small, dependency-free library for reading Claude Code's local session data. It models one
external contract — the `~/.claude/projects/**/*.jsonl` transcript layout Claude Code writes — and
turns it into per-session token/cost summaries. It exists because two members need this exact
parsing: the `usage-dashboard` app and the `usage-report` CLI.

## Commands

See README.md for the public API. Managed with `uv`. For a quick sanity check, parse/type-check the
changed file (`uv run python -m py_compile src/claude_usage/<file>.py`); lint/type-check with
`uv run ruff check .` and `uv run mypy src`.

## Code structure (`src/claude_usage/`)

- `__init__.py` — the public surface (`__all__`). This is the API boundary.
- `sessions.py` — transcript discovery and parsing: `parse_file` (one file, deduped within it),
  the global merge behind `load_usage` / `load_sessions`, `transcript_files`, `claude_dirs`, and
  the `Session`, `MessageUsage`, `UsageEvent`, `FileParse` dataclasses.
- `pricing.py` — the pricing tables and cost math: `price_for` (`MODEL_PRICES` by model-id
  prefix, then the `MODEL_COSTS` family fallback), `estimated_cost`, `model_family`,
  `model_costs`.

## Invariants — do not break these

- **This is a library: keep `dependencies = []`.** Stdlib only. A library imposes every dependency
  on every consumer — never add web-service deps, and do not add a runtime dependency for what a few
  lines of stdlib do.
- **The public API is `__init__.py` / `__all__`.** Anything not exported is private. Treat public
  signature changes as semver-relevant; do not break consumers (`usage-dashboard`, `usage-report`)
  casually.
- **Cost is estimated, never billed.** `estimated_cost` is token counts × list price from
  `price_for`: the longest matching model-id prefix in `MODEL_PRICES`, else the family row in
  `MODEL_COSTS`, else unpriced ($0). When Anthropic changes pricing or ships a model, add or edit
  its `MODEL_PRICES` row; if a model id is misfamilied, fix `model_family`.
- **Dedup is global.** A reply counts once per `message.id` + `requestId` across all files (last
  line's usage, first session seen), and a tool call once per block `id`. `TokenCounts` keys never
  overlap (`cache_write` is 5-minute writes, `cache_write_1h` 1-hour writes), because consumers
  sum the values.
- **Honour `$C4_CLAUDE_DIR`** (pathsep-separated) for config-dir resolution via `claude_dirs`.

## Conventions

- Google-style docstrings on public symbols; type hints everywhere; mypy `strict = true`; ruff
  (line length 88). Never edit `uv.lock` by hand.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
