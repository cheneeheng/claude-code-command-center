---
title: marketplace-updater, install into ~/.claude-command-center instead of LOCALAPPDATA
status: built
created: 2026-11-05
---

## Goal

Move marketplace-updater's install dir (worker copy, `config.json`, `run.log`) from
`%LOCALAPPDATA%\claude-automation\marketplace-updater\` to
`~/.claude-command-center/marketplace-updater/`, so every file the command-center tools own sits
next to its manifest. The flow that matters: re-running install moves an existing install over
with its log, and the scheduled task runs the new copy.

## Scope

**In:**

- `marketplace-updater-setup.ps1`: `-InstallDir` default becomes
  `Join-Path $HOME '.claude-command-center\marketplace-updater'`.
- Migration on install, after the task is re-registered with `-Force` (which repoints it at the
  new worker), so a failed registration never leaves the task pointing at a deleted worker: when
  the old default dir exists and differs from `-InstallDir`, move its `run.log` into the new dir if
  the new dir has none, then delete the old dir. A run in progress can lock `run.log`, so a failed
  move or delete warns and names the old dir instead of throwing.
- Uninstall also deletes the old default dir if it is still there.
- README, CLAUDE.md, `product/ARCHITECTURE.md` (Key Decision), the original plan's
  "Install location" line is left as written, since a built plan is a record.
- `setup/`: the descriptor's calls are unchanged; setup README / ARCHITECTURE wherever they name
  this member's install path.
- `VERSION` minor bump.

**Out:**

- A Linux/macOS twin: still out, as in the original plan.
- Carrying the old `config.json` over: install always rewrites it from `-Marketplaces` / `-Repos`,
  which are required.

## Phases

### Phase 1: setup default and migration

- **Check:** `tests/updater.ps1` still passes (it runs the worker, not the setup). Then, with a temp
  `-InstallDir` and a fake old dir holding a `run.log`, a migration test added to `tests/` that
  runs only the move logic is more ceremony than the change earns, so instead: run
  `setup/command-center.ps1 install -Member marketplace-updater` on this machine (the user's
  `config.json` holds the marketplaces and repos), and
  assert the task action points at the new worker, `run.log` moved, the old dir gone, and
  `-DryRun` of the new worker exits `0`.

### Phase 2: docs and setup/

- **Check:** CI `marketplace-updater.yml` green on the PR, and
  `git grep -n 'claude-automation.marketplace-updater'` matches only plans, records and the
  migration code.

## Record

- 2026-11-05: Plan reviewed in a fresh context: ready to build, three advisory findings folded in.
- 2026-11-05: Built. `tests/updater.ps1` passes. `setup/command-center.ps1 install -Member
  marketplace-updater` on this machine: the task runs
  `~/.claude-command-center/marketplace-updater/marketplace-updater.ps1`, `run.log` moved over
  with its history from 2026-10-21, the old `%LOCALAPPDATA%` dir is gone, and the new worker's
  `-DryRun` exits 0 with "0 failure(s)".
