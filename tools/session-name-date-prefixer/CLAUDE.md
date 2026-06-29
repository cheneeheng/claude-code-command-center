# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A `claude` CLI wrapper that auto-injects a dated `--name <cwd>-<yyMMddHHmm>` when the user does not
pass `--name`/`-n`, so session history is easy to browse. Placed on `PATH` ahead of the real
binary, it passes every argument through unchanged except for that one addition.

## Running

See README.md for install/uninstall. Files:

- `session-name-date-prefixer.ps1` / `.sh` — the wrappers (Windows / Linux-macOS).
- `session-name-date-prefixer-setup.ps1` / `.sh` — installers; install puts the wrapper on `PATH`
  ahead of the real `claude`, uninstall reverses it.

## Invariants — do not break these

- **Pass-through is sacred.** Forward every argument to the real `claude` unchanged. The only
  modification is prepending `--name` when both `--name` and `-n` are absent. Never drop, reorder,
  or rewrite other arguments.
- **Only inject when the user gave no name.** If `--name`/`-n` is present, change nothing.
- **The wrapper must locate and exec the real `claude`, not itself** — it sits ahead on `PATH`;
  preserve the resolution that avoids infinite recursion.
- **Keep the `.ps1` and `.sh` wrappers behaviourally identical.**

## Conventions

- PowerShell + Bash tool; no Python, no dependencies.
- Also installable via the repo-wide `setup/` orchestrator.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
