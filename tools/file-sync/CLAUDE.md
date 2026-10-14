# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Keeps a single named file in sync between two folders chosen at install time, always copying from
the newer file over the older. One generic engine plus two ready-made specializations (CLAUDE.md
raw copy; settings.json copy-with-key-preservation). Each install registers a Windows Task
Scheduler job that runs the engine on an interval through `conhost.exe --headless`, so no
window appears.

## Running

See README.md for full usage. Quick map:

- `sync-engine.ps1` — the generic newer-wins engine (`-FileA`/`-FileB`, `-Strategy raw|json-merge`,
  `-ExcludePaths`).
- `sync-setup.ps1` — generic install/uninstall (Task Scheduler).
- `claude-md-sync-setup.ps1` / `settings-sync-setup.ps1` — thin wrappers that fix `-FileName` and
  `-Strategy` and pass folder/interval args through to `sync-setup.ps1`.

## Invariants — do not break these

- **Newer file always wins.** That is the entire conflict policy for `raw`. Do not introduce
  prompts, three-way merges, or reverse-direction copies into the engine.
- **`json-merge` preserves machine-specific keys in the destination** (default exclude
  `statusLine.command`). Keep merge behaviour key-preserving — do not clobber excluded paths.
- **The task launches the engine through `conhost.exe --headless "<pwsh>"`**, never `pwsh`
  directly (its console window flashes even with `-WindowStyle Hidden`). No launcher file is
  generated.
- **Tasks live under the `\ClaudeAutomation\file-sync\` Task Scheduler folder with per-pair names**
  so multiple syncs coexist. Uninstall takes the same two folders used to install — preserve that
  symmetry.
- The wrappers must stay thin: fix the file name + strategy, delegate everything else to
  `sync-setup.ps1` / `sync-engine.ps1`. Do not duplicate engine logic into a wrapper.

## Conventions

- PowerShell 7 (`pwsh`) / Windows Task Scheduler tool; no Python, no pip dependencies. Windows
  PowerShell 5.1 is not supported.
- Also installable via the repo-wide `setup/` orchestrator (it requires config there: folder
  pairs).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
