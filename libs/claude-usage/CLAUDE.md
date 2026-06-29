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
- `sessions.py` — transcript discovery and parsing: `load_sessions`, `transcript_files`,
  `claude_dirs`, the `Session` dataclass.
- `pricing.py` — the pricing table and cost math: `estimated_cost`, `model_family`, `model_costs`,
  `MODEL_COSTS`.

## Invariants — do not break these

- **This is a library: keep `dependencies = []`.** Stdlib only. A library imposes every dependency
  on every consumer — never add web-service deps, and do not add a runtime dependency for what a few
  lines of stdlib do.
- **The public API is `__init__.py` / `__all__`.** Anything not exported is private. Treat public
  signature changes as semver-relevant; do not break consumers (`usage-dashboard`, `usage-report`)
  casually.
- **Cost is estimated, never billed.** `estimated_cost` is token counts × list price from
  `MODEL_COSTS`, keyed by model *family* (so e.g. `claude-opus-4-7`/`-4-8` share a row). When
  Anthropic changes pricing, update `MODEL_COSTS`; if a model id is misfamilied, fix `model_family`.
- **Honour `$C4_CLAUDE_DIR`** (pathsep-separated) for config-dir resolution via `claude_dirs`.

## Conventions

- Google-style docstrings on public symbols; type hints everywhere; mypy `strict = true`; ruff
  (line length 88). Never edit `uv.lock` by hand.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
