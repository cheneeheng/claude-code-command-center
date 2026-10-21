---
title: marketplace-updater, a scheduled refresh of Claude Code marketplaces and their plugins in chosen repos
status: ready
created: 2026-10-21
---

## Goal

A tool that, on a schedule, refreshes a configured list of Claude Code marketplaces and updates the
plugins from those marketplaces that are installed for a configured list of repos. The marketplaces,
the repos, and the schedule are all config, so the user never edits the script. The flow that
matters most: the user installs once with their marketplace and repos, and plugins in those repos
stay current without them running `claude plugin update` by hand.

## Scope

**In:**

- Config of three things: marketplace names `X`, repo folders `Y`, and the run interval.
- Each run refreshes every configured marketplace with `claude plugin marketplace update <X>`.
- Each run updates every plugin from a refreshed marketplace that is installed for a configured repo at
  local or project scope, by running `claude plugin update <id> --scope <scope>` from inside that repo.
- A marketplace whose refresh fails is skipped for that run and counted as a failure.
- A run log and an exit code (`0` ok, `1` bad config, `2` a step failed).
- `-DryRun` shows what would run and changes nothing.
- An installer that registers a Windows Task Scheduler task, and an uninstaller that removes it.
- Registration in `setup/` so `command-center.ps1` can install it with the other tools.
- A test that runs the real worker against a stub `claude` CLI.

**Out:**

- User-scope plugins: they belong to no repo, and the request names repos.
- Passing `-y` to `claude plugin update`: it would auto-accept a command a marketplace declares in an
  unattended run. Such an update fails and is logged for a person.
- Adding or removing marketplaces or plugins: the tool only keeps existing installs current.
- A cron/Linux/macOS twin: file-sync is Windows-only too, and a twin doubles the maintenance for no
  asked-for user.
- Per-repo schedules, a daily-at-time trigger, and a config reload of the interval: one interval is
  the whole schedule request.
- Restarting running Claude Code sessions: `claude plugin update` says a restart applies it.
- Log rotation: `run.log` appends a few lines per updated plugin per run, small enough for years.
  Add rotation if it ever grows.

## Design

- **Stack:** PowerShell 7 and Windows Task Scheduler, like `file-sync`. Reason: it is the repo's
  pattern for scheduled tools and needs no dependency.
- **Mechanism:** shelling out to the `claude` CLI. Reason: the CLI owns marketplace and plugin state,
  so the tool never touches `known_marketplaces.json` or the plugin cache. `claude plugin list --json`
  gives each install with `scope` and `projectPath`, which is how an installed plugin maps to a repo.
- **Components:**

  ```mermaid
  flowchart LR
      task["Task Scheduler<br/>every N minutes"] --> worker["marketplace-updater.ps1"]
      cfg[("config.json<br/>marketplaces, repos")] --> worker
      worker -->|"marketplace update X"| cli["claude CLI"]
      worker -->|"plugin list --json"| cli
      worker -->|"plugin update id --scope s<br/>cwd = repo"| cli
      worker --> log[("run.log")]
  ```

- **Config** `config.json` in the install dir, re-read every run:
  `{"marketplaces": ["X", ...], "repos": ["path", ...]}`. Editing it needs no reinstall. The interval
  lives in the task trigger, so changing it means re-running install with `-IntervalMinutes`.
- **Install location:** `%LOCALAPPDATA%\claude-automation\marketplace-updater\` holds the worker copy,
  `config.json`, and `run.log`. The task runs that copy, so moving the repo does not break it.
- **Task:** `\ClaudeAutomation\marketplace-updater\marketplace-updater`, launched through
  `conhost.exe --headless pwsh`, repeating every `IntervalMinutes` (1 to 1439, default 360).
- **Interface:** `marketplace-updater.ps1 [-ConfigFile] [-ClaudeCommand] [-DryRun]`;
  `marketplace-updater-setup.ps1 [-Action install|uninstall] [-Marketplaces] [-Repos] [-IntervalMinutes] [-InstallDir]`.
  `-ClaudeCommand` exists so the test can substitute a stub.
- **Matching rule:** a plugin is updated only when its scope is `local` or `project`, its
  `projectPath` equals a configured repo (full path, case-insensitive on Windows), and the part of its
  id after the last `@` is a refreshed marketplace.
  An install listed twice (this machine's list repeats some differing only in the drive-letter case)
  is updated once, keyed on repo, id, and scope. `enabled` is ignored: a disabled install is still an
  install and stays current.
- **A repo with no match** is logged as "nothing to update", so a typo in the config shows up in the log.
- **A failed list is a failed step.** If `plugin list --json` exits non-zero or returns unparseable
  output, the run logs `FAILED listing installed plugins`, writes no "nothing to update" lines, and
  exits `2`. Otherwise a broken list would stop all updates and report success.
- **Unattended means no prompt.** The worker pipes the CLI's output, so the CLI is not on a TTY and
  `plugin update` fails instead of asking, as its `-y` help describes. Every CLI output line is
  written to `run.log`, so the failure and its reason are readable later. The task time limit is 30
  minutes.
- **Why not Claude Code's own marketplace `autoUpdate`:** assumed, not checked, that it refreshes only
  when Claude Code starts and does not update plugins per repo on an interval the user sets. The
  request was a scheduled tool with set marketplaces, repos, and schedule.
- **Test seam:** the test sets `C4_STUB_LIST`, `C4_STUB_LIST_FAIL`, and `C4_STUB_LOG` for the stub CLI.
  They are test-only variables in the repo's `C4_` namespace and are listed in the root `CLAUDE.md`
  and README env table.

## Phases

### Phase 1: Worker and its test

- **Builds:** `marketplace-updater.ps1`, `tests/stub-claude.ps1`, `tests/updater.ps1` (In: refresh,
  update, skip-on-failed-refresh, log and exit codes, `-DryRun`, the test).
- **Check:** `pwsh -NoProfile -File tests/updater.ps1` from `tools/marketplace-updater` prints only
  `ok` lines and exits 0. It covers: update from inside the repo, local and project scope, skips
  (user scope, other marketplace, other repo, failed refresh), a duplicate listed once, `-DryRun`,
  the "nothing to update" line, a missing repo folder, a failed list (exit 2), and an empty config
  (exit 1).
- **Status:** done. `pwsh -NoProfile -File tests/updater.ps1`, run by the user: 12 `ok` lines, no `FAIL`, last line "ok   a config without repos exits 1".

### Phase 2: Installer

- **Builds:** `marketplace-updater-setup.ps1`, `VERSION` (In: install and uninstall of the task).
- **Check:** install with a temp `-InstallDir`, `-Marketplaces no-such-marketplace`, a temp folder as
  `-Repos`, and `-IntervalMinutes 1439`, so a run that fires during the check updates nothing. Then
  `Get-ScheduledTask -TaskPath '\ClaudeAutomation\marketplace-updater\'` returns the task and
  `& <InstallDir>\marketplace-updater.ps1 -DryRun` exits 0. Uninstall with the same `-InstallDir`:
  the task and the folder are gone.
- **Status:** done. Run by the user: install registered the task, `Get-ScheduledTask` showed it `Ready`, the installed worker's `-DryRun` ended with exit `0`, and uninstall removed the task and the folder. The first run failed on a variable clash (`$action` against the `-Action` parameter) and was fixed by renaming it to `$taskAction`.

### Phase 3: Wire into the repo

- **Builds:** the member's `README.md`, `CLAUDE.md`, `product/ARCHITECTURE.md`; the `setup/` registry
  descriptor, example config, and the setup docs that name members; the root README catalog row; a CI
  workflow that runs the test, and the two test-only variables added to the root `CLAUDE.md` var list
  and the root README env table (In: registration in `setup/`).
- **Check:** `pwsh -NoProfile -File setup/command-center.ps1 status` shows `marketplace-updater`
  with version `0.1.0`; `grep -c marketplace-updater` over `README.md`, `setup/README.md`,
  `setup/registry.ps1`, `setup/command-center.config.example.jsonc`, `setup/product/ARCHITECTURE.md`,
  and `.github/workflows/marketplace-updater.yml` is above 0 for every file; `grep -c C4_STUB_LIST`
  over the root `CLAUDE.md` and `README.md` is above 0 for both; the `CI · marketplace-updater` job
  passes on the PR.
- **Status:** done except the CI job, which runs on the PR. `command-center.ps1 status` (run by the user) lists "marketplace-updater   not-installed not-installed v0.1.0". `grep -c` counts: `marketplace-updater` in all 6 named files, `C4_STUB_LIST` in `CLAUDE.md` and `README.md`.

## Open

- Whether `claude plugin update` exits 0 when a plugin is already current. Assumed yes. Phase 2's
  check does not cover it: confirm with one real run before the PR.
- Whether `projectPath` is always present for `project` scope entries. Assumed yes, as it is for
  `local` entries in this machine's `plugin list --json`. Entries without it are skipped.
- Branch protection must mark the new CI check required, which is a GitHub setting this plan cannot change.

## Record

- 2026-10-21 Planned: status ready
- 2026-10-21 Note: the Phase 1 and Phase 2 scripts were drafted before this plan existed. The user asked why the plan came second. The plan above is checked against that draft, and the checks have not been run yet.
- 2026-10-21 Reviewed: Revise first, 2 blocking (plugin list failure exits 0 with "nothing to update"; Phase 3 Check's grep and placeholder subcommand prove nothing, CI unchecked)
- 2026-10-21 Note: both blocking findings and review findings 3 to 11 are now in Design, Out, and the Checks. Phase 3's files were drafted before the review, so they are checked against the plan, not shaped by it. No phase check has run: a worktree guard refuses `pwsh`.
- 2026-10-21 Built Phase 1: `pwsh -NoProfile -File tests/updater.ps1` (run by the user, since the worktree guard refuses `pwsh`), 12 ok lines and no FAIL
- 2026-10-21 Built Phase 2: install, `Get-ScheduledTask` (Ready), installed worker `-DryRun` exit 0, uninstall (run by the user), all passing
- 2026-10-21 Built Phase 3: `command-center.ps1 status` shows marketplace-updater v0.1.0 and the grep counts are above 0 in every named file, CI job pending on the PR
- 2026-10-21 PR: #71 https://github.com/cheneeheng/claude-code-command-center/pull/71
