# Changelog

---

## [0.1.0] — 2026-06-16

Adds an interactive, skill-based way to run the schedulers from inside a Claude Code
session, as an alternative to the cron/Task Scheduler triggers. The triggers call
`claude --print` (programmatic credit); the skills run in your interactive session and
fan work out to subagents instead, so they do not consume programmatic credit.

### Added

- **Interactive skills** — three skills, installed to
  `$CLAUDE_META_DIR/.claude/skills/<name>/SKILL.md` and invokable from a Claude Code
  session opened in the meta repo:
  - `/claude-code-scheduler-daily-summary`
  - `/claude-code-scheduler-daily-lessons`
  - `/claude-code-scheduler-weekly-lessons`

  The daily skills act as a coordinator: they run a prepare script to stage one input
  file per new chat, fan the extraction/summarisation out to subagents (one per chat),
  then `git-sync`. The weekly skill is a single-pass harvest done directly by the
  session (read collected lessons → update master file → advance cursor → `git-sync`).
  Each skill makes one trailing commit after `git-sync` to capture the run log that
  `git-sync` writes *after* committing, leaving a clean working tree. Subagent models
  are pinned: daily-summary on `haiku` (cheap, high-frequency), daily-lessons on
  `sonnet` with high reasoning effort.

- **Prepare scripts** — `daily-summary-prepare`, `daily-lessons-prepare`,
  `weekly-lessons-prepare` (`.sh` + `.ps1`). Same scan / extract / short-session
  filtering as the triggers, but they stop before invoking Claude: they stage per-chat
  input files plus a `manifest.json` (daily) or a single harvest input file (weekly)
  under `$CLAUDE_META_DIR/.claude/scheduler-jobs/<scheduler>/`. That staging directory
  is added to the meta repo `.gitignore` so a partial run is never committed.

- **Install mode selection** — each `install.{sh,ps1}` accepts a mode
  (`skill` / `cron` / `both`, default `both`) that gates which mechanism is installed.
  `setup.{sh,ps1}` now present a split, comma-separated list (skill vs cron variant of
  each scheduler, plus "all") so the two mechanisms can be installed independently.

### Changed

- **Uninstall is grouped by mechanism** in `setup.{sh,ps1}`: cron-based (scheduled
  tasks/cron jobs + trigger + prompt files), skill-based (prepare scripts + skills),
  and an opt-in shared-files removal (`git-sync`, `VERSION`, `scheduler-config.json`).
- Installers require `claude` only for the cron mechanism; skill-only installs need
  just `jq` + `git`. The schedule-time (and weekly day-of-week) prompts now appear only
  when installing the cron mechanism.
- Install progress labels are a running counter (`[1] [2] …`) instead of fixed
  `[n/m]`, so numbering stays correct whichever mode is selected.

---

## [0.0.9] — 2026-05-24

### Added

- **Configurable schedule time** — all three installers (`daily-summary`, `daily-lessons`,
  `weekly-lessons`) now prompt for the run time (HH:MM, 24h) during install instead of
  using a hardcoded value. `weekly-lessons` additionally prompts for day of week.
  Defaults match the previous hardcoded values (`02:00`, `03:00`, `Sunday`) so existing
  users are unaffected if they press Enter through the prompts. Applies to both `.ps1`
  and `.sh` variants.

- **Configurable session filter thresholds** — `daily-summary` and `daily-lessons`
  installers now prompt for `minUserTurns` (default `2`) and `minTranscriptChars`
  (default `500`). Thresholds are persisted to `scheduler-config.json` in the scripts
  dir and read by the trigger scripts at runtime. Trigger scripts fall back to the
  original hardcoded defaults when the file is absent, making the change fully
  backward-compatible with existing installs.

- **`scheduler-config.json`** — new per-install config file written to
  `$META_DIR/.claude/scripts/scheduler-config.json`. Each installer writes or merges
  its own section (`dailySummary`, `dailyLessons`, `weeklyLessons`) so running
  installers independently or in any order preserves all sections.

### Changed

- `weekly-lessons/install.sh` now requires `jq` (added to dependency check) to
  write its section of `scheduler-config.json`.
- Setup banners in `setup.ps1` and `setup.sh` updated to reflect that schedule times
  are now user-configurable rather than fixed.

---

## [0.0.8] — 2026-04-27

### Added

- **File-based logging** — all trigger scripts (`daily-summary`, `daily-lessons`,
  `weekly-lessons`) and `git-sync` now write timestamped `.log` files to
  `$META_DIR/logs/` alongside stdout. Log files are named
  `YYYYMMDD_HHmmss_<script>.log`. Applies to both `.ps1` and `.sh` variants.

### Changed

- **Task Scheduler folder scoping** (`daily-summary/install.ps1`,
  `weekly-lessons/install.ps1`) — tasks are now registered under the
  `\ClaudeCodeScheduler\` folder using `-TaskPath`, preventing name collisions
  with other schedulers. Verification output updated accordingly.
- **`daily-summary-trigger.ps1`** — `claude --print` now passes `--model haiku`
  to reduce cost on high-frequency summarisation runs.
- **Em-dash → hyphen** — replaced `—` with `-` throughout all log messages,
  comments, and output strings for cross-platform terminal compatibility.

---

## [0.0.6] — 2026-04-26

### Added

- `setup.ps1` and `setup.sh` now includes the daily-lessons scheduler.

---

## [0.0.5] — 2026-04-16

### Changes

#### daily-summary, weekly-lessons, git-sync

- **`*-trigger.ps1` / `*-trigger.sh`**, **`git-sync.ps1` / `git-sync.sh`**: Replaced bare
  `Write-Output` / `echo` calls with a `Log` / `log` helper that prepends an ISO-8601
  timestamp to every line (`[YYYY-MM-DD HH:MM:SS] …`). Log output is now consistent across
  all scripts.

#### install scripts

- **`daily-summary/install.ps1` / `.sh`**, **`weekly-lessons/install.ps1` / `.sh`**: Added a
  post-install "Verify the scheduler is running" section that prints four numbered steps —
  confirming registration, watching the log in real time, triggering a manual test run, and
  checking output files. Replaces the previous ad-hoc "run manually" hint with actionable
  verification commands.

---

## [0.0.4] — 2026-04-15

### Changes

#### weekly-lessons

- **`weekly-lessons-trigger.ps1` / `.sh`**: Replaced git clone logic with local file
  reads. Repos are now configured by local path instead of URL + branch. If a configured
  path or its lessons file is not found, a warning is emitted and the harvest continues
  with the remaining repos.
- **`scheduled-repos.json`**: Replaced `url` and `branch` fields with `path` (absolute
  local path to the repo directory).

#### docs

- Extracted detailed scheduler documentation from `README.md` into
  `daily-summary/README.md`, `weekly-lessons/README.md`, and `git-sync/README.md`.
- Root `README.md` is now a concise overview with links to the detail docs.

---

## [0.0.3] — 2026-04-06

### Enhancements

#### daily-summary

- **`daily-summary.md`**: Added three new sections to the summary template —
  `## Current State` (files created/modified/deleted), `## Pending / Next Steps`
  (checkbox list of incomplete work), and `## Key Facts for Next Session`
  (non-obvious facts to avoid repeated mistakes). All sections follow the existing
  `<...>` instruction-comment style and are skippable when not applicable.
- **`daily-summary.md`**: Removed the `/summarize-chat` skill branch from Step 2;
  the prompt now instructs Claude to write the summary directly.

---

## [0.0.2] — 2026-04-06

### Bug fixes and consistency improvements

#### daily-summary

- **`daily-summary.md`**: Fixed cross-platform path format (`$env:CLAUDE_META_DIR\...` →
  `$CLAUDE_META_DIR/...`). The prompt file is shared between Windows and Linux; the old
  PowerShell-specific syntax would not resolve correctly on Linux.
- **`daily-summary.md`**: Step 2 now mentions that if the `/summarize-chat` skill is
  available, it should be invoked to produce the summary instead of writing it manually.
- **`install.ps1`**: Removed inaccurate footer line ("only runs if /summarize-chat was
  called") — the trigger scans all modified chat files regardless. Removed the unrelated
  CLAUDE.md suggestion block. Footer now matches `install.sh`.

#### weekly-lessons

- **`weekly-lessons.md`**: Fixed cross-platform path formats (same issue as daily-summary).
- **`weekly-lessons-trigger.ps1`**: Added missing `git-sync.ps1` existence check at startup,
  consistent with the guard already present in `daily-summary-trigger.ps1`. Moved `$GitSync`
  variable declaration to the top-level guard section and removed the duplicate late assignment.
- **`weekly-lessons-trigger.sh`**: Same fix — added missing `git-sync.sh` existence check and
  moved `GIT_SYNC` variable to the guard section.
- **`install.ps1`**: Removed the bogus `[7/7] Done.` step (the header comment listed 6 actual
  steps; the script now uses `[1/6]`–`[6/6]`). Aligned `Output:` line format with `install.sh`.
  Fixed "in your shell" wording to match the other install scripts.
- **`install.sh`**: Added "The harvest runs every Sunday at 02:00." line to the footer, matching
  the equivalent line already present in `install.ps1`.

---

## [0.0.1] — 2026-04-06

Initial implementation.

### Schedulers

#### daily-summary
Runs at 02:00 daily. Scans `~/.claude/projects/**/*.jsonl` for chat sessions
modified since the last run, extracts each transcript, and passes it to Claude
for summarisation. One `.md` file is written per session under
`daily-summaries/YYYY/MM/`. Short sessions (fewer than 2 user turns or fewer
than 500 chars) are skipped. A single git commit is made after all chats are
processed.

#### weekly-lessons
Runs at 02:00 every Sunday. Clones each repo listed in
`$CLAUDE_META_DIR/.claude/scheduled-repos.json`, reads its `LESSONS_LEARNED.md`,
and passes the collected content to Claude. Claude filters for project-generic
lessons, deduplicates against the existing master file, and appends new entries to
`master-lessons/MASTER_LESSONS_LEARNED.md`. Clones are deleted immediately after
reading. The harvest is idempotent (git log check prevents double-runs).

#### git-sync
Shared utility called by both schedulers after Claude writes output. Runs
`git add -A`, commits with a `<label>: <timestamp>` message, and pushes if a
remote is configured.

### Platform support

| Platform | Scheduling | JSON parsing | Scripts |
|----------|-----------|--------------|---------|
| Windows  | Task Scheduler | PowerShell built-in | `.ps1` |
| Linux    | cron | `jq` | `.sh` |

Prompt files (`daily-summary.md`, `weekly-lessons.md`) and
`scheduled-repos.json` are shared across platforms.

### Setup

Interactive CLI (`setup.ps1` / `setup.sh`) handles install and uninstall.
Prompts for the `claude-meta` directory, validates or initialises it as a git
repo, sets `CLAUDE_META_DIR`, and registers the chosen schedulers.

On Linux, `CLAUDE_META_DIR` is written to `~/.claude/claude-scheduler.env` so
cron jobs can source it at runtime.

### Output locations

```
$CLAUDE_META_DIR/
  daily-summaries/YYYY/MM/   <- session summaries (daily-summary)
  master-lessons/            <- MASTER_LESSONS_LEARNED.md (weekly-lessons)
  lessons-learned/           <- manual /lessons-learned skill output
  logs/                      <- trigger logs (Linux only)
  .claude/
    scripts/                 <- installed trigger scripts and prompts
    settings.json            <- Claude tool permissions
    scheduled-repos.json     <- repo list for weekly-lessons
```
