# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code `StatusLine` hook that prints a colour-coded one-liner each turn
(`model | context bar | runtime | cost | 5h rate | 7d rate`). It can also append the turn to
`~/.claude/statusline/<project>/<session_id>.jsonl`, which powers the live rate-limit panel in the
`usage-dashboard` app.

## Implementations — keep all three in step

Three equivalent implementations, one per shell. A behaviour change to one must be mirrored in the
others:

- `statusline-hook.ps1` — Windows (PowerShell); forces UTF-8 output.
- `statusline-hook.sh` — Linux / macOS (Bash); requires `jq`.
- `statusline-hook.py` — cross-platform (Python stdlib); UTF-8-safe stdin/stdout.

## Running / checking

See README.md for setup (`statusline-hook-setup.ps1`, `-Variant`, `-Action uninstall`) and the
manual `settings.json` wiring. The `pyproject.toml` exists **only** to satisfy the monorepo
"every Python member is a `uv` project" rule and to hold shared ruff/mypy config — the hook is not
an installable package (`dependencies = []`, `[tool.uv] package = false`); all three scripts run
directly. `uv sync` is needed only to lint/type-check the Python variant:

```
uv run ruff check .
uv run mypy statusline-hook.py
```

## Invariants — do not break these

- **The JSONL export is opt-in and off by default.** It runs only when `C4_STATUSLINE_EXPORT` is
  `1`/`true`/`yes`. Unset → print the status line and write nothing. Do not make the export
  unconditional; the dashboard treats it as optional.
- **Export record shape is `{session_id, ts, data}`** at
  `~/.claude/statusline/<project>/<session_id>.jsonl` — this is the contract `usage-dashboard`
  reads. Change both ends together.
- **Honour `$C4_CLAUDE_DIR`** (pathsep-separated) for the base config dir; `-ClaudeDir` overrides.
- **Nothing beyond the script is required to run the hook.** Keep the Python variant stdlib-only.

## Conventions

- Cross-platform; primary dev platform is Windows (PowerShell), Bash tool also available. Keep the
  three implementations behaviourally identical.
- Also installable via the repo-wide `setup/` orchestrator
  (`command-center.ps1 install -Member statusline-hook`).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
