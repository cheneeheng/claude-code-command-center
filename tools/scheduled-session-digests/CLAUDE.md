# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A background pipeline that turns Claude Code sessions into lessons learned, using headless
`claude --print` with fixed prompts. It installs into a meta repo (`claude-meta`); a daily job
writes one lessons file per session, a weekly job merges generic lessons into a master file,
and every session's cleaned transcript is archived. PowerShell 7.4+ on Windows, Bash 4+ with
`jq` on Linux. README.md covers usage.

## Layout

- `lessons.ps1` / `lessons.sh`: the CLI (`install`, `run`, `status`, `uninstall`), run from the
  clone. `install` copies `src/` into `<meta>/.claude/session-lessons/src/`.
- `src/`: the installed pipeline. The scripts find the meta repo from their own location, never
  from an environment variable.
  - `run`: the only consumer: lock, cutoff, prepare, one claude call per session (daily) or
    batch (weekly), finish. `-Scheduled` applies the due rule.
  - `prepare` / `prepare-weekly`: scanning, filtering, cleanup, archiving, staging.
  - `finish` / `finish-weekly`: split, validate, move into place, attempts, cursors, the
    last-run summary.
  - `git-sync`: commit and push.
  - `lib.ps1` / `lib.sh`: shared helpers (lock, due rule).
  - `clean.jq`, `split.jq`, `merge.jq`: the Bash cleanup, answer split, and weekly merge.
  - `prompts/`: `daily-frame.md`, `extract/<extraction>.md`, `merge/<extraction>.md`.
  - `config.default.json`: the defaults `install` writes.
- `tests/run.sh <bash|pwsh> [suite]`: suites `archive`, `daily`, `weekly`, `cli`,
  `equivalence`. A fake `claude` (`tests/fake-claude.{sh,ps1}`) answers.

## Invariants — do not break these

- **The PowerShell and Bash implementations behave the same, byte for byte.** Every rule exists
  in both (`clean.jq` ↔ `Convert-Transcript`, `split.jq` ↔ `Split-Answer`, `merge.jq` ↔
  `Merge-WeeklyAnswer`, each script ↔ its twin), each file names its twin in a
  `Cross-reference:` comment, and the `equivalence` suite diffs their outputs. A behaviour
  change is the same edit in both plus a passing `equivalence` run.
- **One claude call per session carries every extraction it still needs.** The prompt is
  `daily-frame.md` plus each needed `extract/<name>.md`; the answer is split on whole-line
  `<<<extraction:NAME>>>` markers (text before the first ignored, unrequested names ignored,
  first occurrence wins, a fence around a part dropped). Each part is validated on its own and
  a valid part is kept even when another fails.
- **Claude writes nothing and uses no tools.** It runs with `--tools "" --no-session-persistence`
  and answers on stdout; the scripts write every file. Only validated output is moved into
  place, so a killed run never leaves a partial file.
- **The cleanup rules are versioned.** Any change to what `clean.jq` / `Convert-Transcript`
  keeps or drops bumps `Cleanup: v1` in the archive header. `[USER]` holds only what the user
  typed; injected text (hook output, reminders, command output, compaction summaries) never
  reaches it.
- **Cursors never skip work.** A cursor moves to the smaller of the run's `cursorEpoch` and the
  oldest undone session minus 1 second; only runs whose cutoff is at or before the stored
  cursor move it; `-DryRun` and `-ArchiveOnly` never write a cursor or a last-run file. A
  `claude` failure stops the run and counts no attempt.
- **One run per meta repo at a time** (`state/run.lock`, PID plus start time; replaced only
  when that process is gone).
- **`git-sync` is the only writer of git history** in the meta repo.
- **Uninstall never deletes the meta repo or its `.git`.** `-Purge` deletes only this tool's
  paths. Install removes only previous-version items that point at the meta repo being
  installed.
- **Test fixtures are synthetic.** This repo is public: fixtures copy the structure of real
  transcripts with made-up text, never real lines. A local test run never registers a real
  scheduled task; that runs only with `CI=true`.
- **No new environment variables.** Plumbing between the scripts goes through arguments. The
  only variables read are `C4_CLAUDE_META_DIR` (default meta dir) and `C4_CLAUDE_DIR` (scan
  roots, read at install).
- Scheduled entry: Windows task `\ClaudeAutomation\scheduled-session-digests\SessionLessons-<8 hex of the meta path's SHA-256>`;
  Linux crontab line ending `# session-lessons:<meta>`.

## Conventions

- Version lives in `VERSION`; release tag `ssd-vX.Y.Z` (see `docs/releasing.md`), changes in
  `CHANGELOG.md`.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
