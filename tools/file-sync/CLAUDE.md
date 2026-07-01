# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Keeps a single named file in sync between two folders chosen at install time, always copying from
the newer file over the older. One generic engine plus two ready-made specializations (CLAUDE.md
raw copy; settings.json copy-with-key-preservation). Each install registers a Windows Task
Scheduler job that runs on an interval via a hidden VBS launcher.

## Running

See README.md for full usage (run as Administrator). Quick map:

- `sync-engine.ps1` — the generic newer-wins engine (`-FileA`/`-FileB`, `-Strategy raw|json-merge`,
  `-ExcludePaths`).
- `sync-setup.ps1` — generic install/uninstall (Task Scheduler + hidden VBS).
- `claude-md-sync-setup.ps1` / `settings-sync-setup.ps1` — thin wrappers that fix `-FileName` and
  `-Strategy` and pass folder/interval args through to `sync-setup.ps1`.
- `hidden.vbs` — reference template only.

## Invariants — do not break these

- **Newer file always wins.** That is the entire conflict policy for `raw`. Do not introduce
  prompts, three-way merges, or reverse-direction copies into the engine.
- **`json-merge` preserves machine-specific keys in the destination** (default exclude
  `statusLine.command`). Keep merge behaviour key-preserving — do not clobber excluded paths.
- **Generated launchers are per-(file, folder-pair) and gitignored.** Install writes one
  `file-sync-<hash>-hidden.vbs` embedding resolved local paths. Never commit a generated VBS and
  never hand-edit `hidden.vbs` as if it were live config — it is a template.
- **Tasks live under the `\ClaudeAutomation\file-sync\` Task Scheduler folder with per-pair names**
  so multiple syncs coexist. Uninstall takes the same two folders used to install — preserve that
  symmetry.
- The wrappers must stay thin: fix the file name + strategy, delegate everything else to
  `sync-setup.ps1` / `sync-engine.ps1`. Do not duplicate engine logic into a wrapper.

## Conventions

- PowerShell / Windows Task Scheduler tool; no Python, no pip dependencies.
- Also installable via the repo-wide `setup/` orchestrator (it is the one member that requires
  config — folder pairs).
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
