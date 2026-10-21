# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A scheduled job that refreshes configured Claude Code marketplaces and updates the plugins from
them that are installed for configured repos. It only shells out to the `claude` CLI and never
touches Claude Code's own state files.

## Running

See `README.md`. Install via `marketplace-updater-setup.ps1`, or through `setup/command-center.ps1`
(descriptor `marketplace-updater`, `RequiredConfig = @('marketplaces', 'repos')`).

## Architecture

- `marketplace-updater.ps1` — the worker. Reads `config.json` next to it, refreshes each
  marketplace, then updates matching installs. Copied into the install dir by setup.
- `marketplace-updater-setup.ps1` — install/uninstall. Copies the worker, writes `config.json`,
  registers `\ClaudeAutomation\marketplace-updater\marketplace-updater` (every `IntervalMinutes`,
  through `conhost.exe --headless pwsh`).
- `tests/updater.ps1` + `tests/stub-claude.ps1` — the real worker against a stub `claude`.
- Plan and design: `product/plans/marketplace-updater.md`, `product/ARCHITECTURE.md`.

## Invariants — do not break these

- **A plugin is updated only when all three hold:** scope is `local` or `project`, its
  `projectPath` is a configured repo, and its marketplace (the id after the last `@`) refreshed
  successfully this run. Never widen this to user scope: those installs belong to no repo.
- **Never pass `-y` to `claude plugin update`.** The run is unattended, and `-y` would auto-accept
  a command a marketplace declares. A failing update is logged for a person.
- **`claude plugin update` runs with the repo as the working directory** and an explicit
  `--scope`. Scope auto-detection depends on the working directory.
- **A failed `plugin list` exits `2`, never "nothing to update".** A broken list would otherwise
  stop every update and report success.
- **One failure must not abort the run.** Log it, count it, continue, and exit `2` at the end.
  Exit `1` is for a missing or invalid config.
- **`Log` writes with `Write-Host`**, so a function that logs can also return a value.
- **Only the CLI changes plugin state.** Do not edit `known_marketplaces.json` or the plugin cache.

## Conventions

- PowerShell 7 (`pwsh`) and Windows Task Scheduler; no dependencies. The `VERSION` file tracks
  this component's release.
- Keep `setup/registry.ps1` and `setup/command-center.config.example.jsonc` in step with the
  setup script's parameters and the config keys.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
