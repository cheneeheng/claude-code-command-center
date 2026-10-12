# Changelog

All notable changes to `scheduled-session-digests` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Releases are tagged `ssd-vX.Y.Z`, and the tool
installs from a clone at that tag.

## [Unreleased]

## [0.2.0] - 2026-10-13

First tagged release: a from-scratch rebuild as a headless background pipeline that ships
lessons learned ([#62](https://github.com/cheneeheng/claude-code-command-center/pull/62)).

### Added

- One CLI, `lessons.ps1` (Windows, PowerShell 7.4+) and `lessons.sh` (Linux, Bash 4+ with `jq`),
  with `install`, `run`, `status`, and `uninstall`, and `-MetaDir` on every command.
- `install` asks no questions: it lists every change it will make and applies them on
  confirmation, with a flag for each setting.
- One hourly scheduled entry per meta repo that runs whichever daily or weekly job is due, so a
  job missed while the machine was off runs at the next tick.
- One `claude --print` call per session that carries every extraction the session still needs.
  Each part of the answer is validated and filed on its own.
- A cleaned transcript archive in `transcripts/`, versioned with `Cleanup: v1`, and a one-time
  archive of every session still on disk at install.
- Bounded runs: a first run covers the last 7 days unless `-All` is passed, a scheduled run
  processes at most 20 sessions, and a manual run shows a preview with a rough token count
  before it starts.
- `status`: the schedule, the next runs, progress, the last run's error, and given-up sessions.
- `uninstall -Purge` to remove this tool's data as well. A plain `uninstall` keeps every
  lessons file, the archive, the logs, and `config.json`.
- A failed `git add` or `git commit` is reported as the run's error: `status` shows it and the
  next hourly check retries. A failed push is only a warning.

### Changed

- **Breaking:** `install` replaces the previous version's scheduled tasks, cron lines, scripts,
  and interactive skills, but only those that point at the meta repo being installed. It
  carries over the progress markers and schedule settings, and keeps every lessons file and the
  master file.
- Claude runs with tools disabled and is never saved as a session (`--tools ""`,
  `--no-session-persistence`). It answers on stdout, and only validated output is moved into
  place, so a killed run never leaves a partial file.
- The weekly merge sends Claude the existing lesson titles instead of the whole master file.
- A `claude` failure stops the run and counts no attempt against any session. A session whose
  answer is invalid 3 times is given up.
- Windows needs PowerShell 7.4 or newer. `install` records the native `claude.exe` ahead of any
  `claude.ps1` wrapper earlier on PATH, because a wrapper may not pass the transcript on.
- `setup/command-center.ps1` now installs this tool through `lessons.ps1`.

### Removed

- The daily-summary job. Existing `daily-summaries/` files are left in place.
- The interactive `/session-digest-*` skills.
- `setup.ps1` and `setup.sh`, and the per-scheduler folders and READMEs (`daily-summary/`,
  `daily-lessons/`, `weekly-lessons/`, `git-sync/`, `lib/`, `skills/`).
