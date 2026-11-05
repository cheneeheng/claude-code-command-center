# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file tkinter widget (`claude_usage_widget.pyw`) that shows the Claude 5-hour and 7-day
usage limits from the undocumented `api/oauth/usage` endpoint. Windows only (`ctypes.windll`).

## Commands

```
uv run ruff check . && uv run ruff format --check .   # .pyw is included via extend-include
pwsh -File usage-limit-widget-setup.ps1 [-Action uninstall]
```

`setup/registry.ps1` delegates to the setup script and detects the install by the
`\ClaudeAutomation\usage-limit-widget\widget` task, so a change to the script's name,
parameters, or task name must update `setup/` in the same change.

## Invariants — do not break these

- **Tk calls stay on the main thread.** The fetch thread only assigns `self.data`. `r` only sets
  an `Event` that wakes the fetch loop.
- **The task's restart is the lifecycle.** The task repeats hourly with `MultipleInstances =
  StopExisting`, so each start replaces the running widget. Keep `ExecutionTimeLimit` at zero
  and the battery flags off, or the task kills the widget on its own.
- **The task runs a base interpreter's `pythonw.exe`** (`uv python find --system`), never the
  `.venv` one, which is git-ignored and is a redirector that spawns a second process.
- **Keep the panel tight vertically:** one row per limit, no title row.

## Conventions

- Stdlib only: `dependencies = []`, `[tool.uv] package = false`.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
