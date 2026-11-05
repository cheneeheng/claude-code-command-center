---
title: agents-workspace-sync, keep its worker, config and logs under ~/.claude-command-center
status: built
created: 2026-11-05
---

## Goal

Move everything agents-workspace-sync installs or writes out of the claude-meta repo into its own
folder, `~/.claude-command-center/agents-workspace-sync/`, and drop its dependency on
`C4_CLAUDE_META_DIR`. The flow that matters: a user who has never heard of claude-meta installs
the tool, and the nightly job commits and pushes their `.agents_workspace` repos, with every file
it owns in one folder next to the command-center manifest.

## Scope

**In:**

- New layout, the same on Windows and Linux/macOS:

  ```
  ~/.claude-command-center/agents-workspace-sync/
    agents-workspace-sync.ps1 | .sh   the installed worker
    VERSION
    config.json                       {scheduleTime, repos[]}
    logs/<yyyy>/<MM>/<yyyyMMdd_HHmmss>_agents-workspace-sync.log
    cron.log                          (.sh only: the cron line's stdout/stderr)
  ```

- Worker (`.ps1` and `.sh`, kept equivalent): the default config is `config.json` next to the
  worker, logs go under `logs/` next to the worker. `C4_CLAUDE_META_DIR` is no longer read, so the
  "meta dir not set" exit is gone. Exit `1` stays for no config or no repos.
- Setup: `-MetaDir` / `--meta-dir` replaced by `-InstallDir` / `--install-dir`, default as above.
  Setup no longer creates or `git init`s claude-meta and no longer sets `C4_CLAUDE_META_DIR`.
- Migration on install from the old location (`$C4_CLAUDE_META_DIR`, else `~/claude-meta`, then
  `.claude/scripts/`): an interactive install pre-fills the repo list from the old
  `agents-workspace-sync-config.json` when the new `config.json` does not exist yet, and every
  install deletes the old worker, `agents-workspace-sync.VERSION` and old config after writing the
  new ones. Old logs under `<meta>/logs/` are left where they are: they sit in the digests' log
  tree, which this tool does not own. The three old files are tracked in claude-meta's git, so
  the deletions get committed by the digests' git-sync; setup prints that. An old install at a
  custom `metaDir` (recorded only in the manifest) is not found: accepted, the setup prints the
  path it looked in, and the user can delete leftovers by hand.
- A `logs/` entry in the member's `.gitignore`, because the worker writes `logs/` next to itself
  and someone running it from the checkout would otherwise leave untracked logs in the repo.
- The `.sh` crontab line loses its inline `C4_CLAUDE_META_DIR=` and redirects to `cron.log` in the
  install dir. It keeps the `# agents-workspace-sync` marker, so install replaces the old line.
- Uninstall removes the task (or crontab line), the worker, `VERSION`, and `config.json` (unless
  `-KeepConfig`), and leaves `logs/`. It also deletes old-location files if any are left.
- `setup/` in step: `registry.ps1` stops passing `metaDir` (an old manifest entry that carries it
  is ignored, which is safe because install migrates), `command-center.config.example.jsonc` drops
  the "metaDir defaults like the digests'" note, and setup's README / ARCHITECTURE wherever they
  name this member's paths, including `setup/README.md` line 63 (this member's uninstall replays
  recorded params) and the root `README.md` line that lists this member as a reader of
  `C4_CLAUDE_META_DIR`.
- README, CLAUDE.md (the invariant "Honour `$C4_CLAUDE_META_DIR` ... abort when it is unset" is
  replaced by "everything lives under the install dir"), `product/ARCHITECTURE.md` with a Key
  Decision. Root CLAUDE.md env var list: `C4_CLAUDE_META_DIR` is described as read only by
  scheduled-session-digests, which is already true of its text, so no change there.
- `VERSION` minor bump.

**Out:**

- A `C4_` env var for the new home: the setup parameter covers the override, and no one asked.
- Moving old logs: they share a tree with the digests' logs.
- Tests: the member has none today. The change is path wiring, checked by a dry run (below).

## Design

- The worker finds its home from its own location (`$PSScriptRoot`, `BASH_SOURCE`), the same way
  marketplace-updater finds `config.json`. So a non-default `-InstallDir` needs nothing extra.
- Config file name becomes `config.json` because the folder already names the tool.
- The task action and the crontab line point at the installed worker, so re-running install
  repoints an existing task (`Set-ScheduledTask` path already in setup).

## Phases

### Phase 1: worker and setup, both shells

- **Worker check (both shells, no setup):** in a temp folder, a scratch git repo with a bare
  remote and a `config.json` naming it next to a copy of each worker. Run each worker with
  `C4_CLAUDE_META_DIR` unset: `-DryRun` / `--dry-run` exits `0` and writes a log under
  `<temp>/logs/<yyyy>/<MM>/`, a real run pushes the scratch commit to the bare remote.
- **`.sh` setup check:** Git Bash has no `crontab`, so run the `.sh` setup with a stub `crontab`
  first on PATH that reads and writes a temp file, `HOME` and `C4_CLAUDE_META_DIR` at temp dirs,
  and a fake old `<meta>/.claude/scripts/` holding the three old files. Assert the cron line names
  the new worker and `cron.log`, the old files are gone, and uninstall removes the line and files
  but keeps `logs/`.
- **`.ps1` setup check, on this machine:** the setup has no task-name parameter, so a test install
  would repoint the real task. Instead the real install is the check: run
  `setup/command-center.ps1 install -Member agents-workspace-sync` (the user's config holds the
  repos), then assert the task action names
  `~/.claude-command-center/agents-workspace-sync/agents-workspace-sync.ps1`, the new
  `config.json` holds the same repos as the old one, the old files under
  `~/claude-meta/.claude/scripts/` are gone, and the installed worker's `-DryRun` exits `0`.

### Phase 2: setup/ and docs

- **Check:** `command-center.ps1 status` lists the member as installed, and
  `git grep -n -e '.claude/scripts' -e 'agents-workspace-sync-config'` matches only plans,
  records and the migration code.

## Record

- 2026-11-05: Plan reviewed in a fresh context: two blocking findings (checks that would touch the
  real claude-meta and task; no `crontab` in Git Bash) and five advisory ones, all folded in above.
- 2026-11-05: Built. Worker check: both workers' dry runs exit 0 with a log under
  `logs/<yyyy>/<MM>/`, and real runs push to a scratch bare remote. `.sh` setup check (stub
  `crontab`, temp `HOME`): one cron line naming the new worker and `cron.log`, other lines kept,
  old files deleted, uninstall keeps `logs/`. Real install on this machine: the task now runs
  `~/.claude-command-center/agents-workspace-sync/agents-workspace-sync.ps1`, its dry run reports
  "all 6 repo(s) ok", and the three old files are gone from `~/claude-meta/.claude/scripts/`.
  Ran the member's setup directly, not `command-center.ps1 install`, because the user's
  command-center `config.json` lists 4 repos while the live config listed 6.
