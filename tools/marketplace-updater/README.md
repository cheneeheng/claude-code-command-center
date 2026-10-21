# marketplace-updater

Keeps Claude Code plugins current on a schedule. Every run refreshes the marketplaces you list,
then updates the plugins from those marketplaces that are installed for the repos you list.
The marketplaces, the repos, and the interval are all config.

Windows only: PowerShell 7 (`pwsh`) and Task Scheduler, plus the `claude` CLI on `PATH`.

## Install

```powershell
.\marketplace-updater-setup.ps1 -Marketplaces my-marketplace -Repos C:\p\repo-a,C:\p\repo-b
.\marketplace-updater-setup.ps1 -Marketplaces my-marketplace -Repos C:\p\repo-a -IntervalMinutes 60
```

| Parameter           | Meaning                                                              | Default |
| ------------------- | -------------------------------------------------------------------- | ------- |
| `-Marketplaces`     | Names as shown by `claude plugin marketplace list`                   | required |
| `-Repos`            | Repo folders whose local/project-scope plugins get updated           | required |
| `-IntervalMinutes`  | How often the task runs (1 to 1439)                                  | `360`   |
| `-InstallDir`       | Where the worker copy, `config.json` and `run.log` go                | `%LOCALAPPDATA%\claude-automation\marketplace-updater` |

Install registers `\ClaudeAutomation\marketplace-updater\marketplace-updater`. Also installable
through `setup/command-center.ps1` (config keys `marketplaces`, `repos`, `intervalMinutes`).

## Change the config

Edit `config.json` in the install dir. It is re-read every run, so marketplaces and repos need no
reinstall:

```json
{ "marketplaces": ["my-marketplace"], "repos": ["C:\\p\\repo-a"] }
```

The interval is part of the scheduled task, so to change it re-run install with the new
`-IntervalMinutes`.

## What a run does

1. `claude plugin marketplace update <marketplace>` for each marketplace. A failure skips that
   marketplace's plugins for this run.
2. `claude plugin list --json`, keeping installs at `local` or `project` scope whose repo is in
   `repos` and whose marketplace was refreshed.
3. `claude plugin update <id> --scope <scope>`, run from inside the repo.

User-scope plugins belong to no repo and are left alone. Claude Code applies an update on its next
restart. No `-y` is passed, so an update that needs a marketplace-declared command confirmed fails
and is logged, with the CLI's output, in `run.log` for you to run by hand.

## Check it works

```powershell
& "$env:LOCALAPPDATA\claude-automation\marketplace-updater\marketplace-updater.ps1" -DryRun   # shows commands, changes nothing
& "$env:LOCALAPPDATA\claude-automation\marketplace-updater\marketplace-updater.ps1"            # run now
Get-Content "$env:LOCALAPPDATA\claude-automation\marketplace-updater\run.log" -Tail 20
```

Exit codes: `0` ok, `1` bad or missing config, `2` a step failed (see `run.log`).

## Uninstall

```powershell
.\marketplace-updater-setup.ps1 -Action uninstall
```

Removes the task and the install dir, including `config.json` and `run.log`.

## Test

```powershell
pwsh -NoProfile -File tests/updater.ps1
```

Runs the real worker against a stub `claude` and checks which commands it issued.
