# scheduled-session-digests

Unattended Claude Code automations that run on a schedule. Output is written to a
shared local git repo (`claude-meta`), which can optionally be pushed to a remote.

| # | Scheduler | Default trigger | What it does |
|---|-----------|-----------------|--------------|
| 1 | [daily-summary](#daily-summary) | 02:00 daily | Reads each Claude Code chat from the last run, summarises it with Claude, writes one `.md` per session |
| 2 | [daily-lessons](#daily-lessons) | 03:00 daily | Reads each Claude Code chat from the last run, extracts lessons learned via the `ceh-lessons-learned` skill, writes one `.md` per session |
| 3 | [weekly-lessons](#weekly-lessons) | Sunday 02:00 | Reads per-session lessons files written by daily-lessons, distils project-generic lessons into a master file |
| 4 | [git-sync](#git-sync) | called by 1, 2, and 3 | Stages, commits (date-stamped), and pushes `claude-meta` after each run |

Trigger times, day of week, and session filter thresholds are set interactively during install. Defaults are shown above.

Both Windows (PowerShell + Task Scheduler) and Linux (Bash + cron) are supported.

---

## Two ways to run each scheduler

Each scheduler (1–3 above) can be installed as either — or both — of:

| Mechanism | How it runs | Cost |
|-----------|-------------|------|
| **cron** | Unattended on a schedule (cron / Task Scheduler). The trigger calls `claude --print`. | Consumes programmatic credit |
| **skill** | On demand from inside a Claude Code session opened in the meta repo, via `/session-digest-<name>`. A prepare script stages the work and the session fans it out to subagents. | Uses your interactive session |

The skill mechanism exists for when programmatic (`claude --print`) usage is limited.
The daily skills act as a coordinator — stage per-chat inputs, spawn one subagent per
chat, then `git-sync`. The weekly skill harvests the collected lessons in a single pass.

Install presents a split list so you can pick any combination, e.g. skills for daily,
cron for weekly. Skills are installed to `$C4_CLAUDE_META_DIR/.claude/skills/` and are
discoverable when you run Claude Code with the meta repo as the working directory.

## Quick start

```powershell
# Windows
git clone <this-repo>
cd scheduled-session-digests
.\setup.ps1
```

```bash
# Linux
git clone <this-repo>
cd scheduled-session-digests
bash setup.sh
```

The CLI prompts for the `claude-meta` directory, initialises it as a git repo,
and installs whichever schedulers and mechanisms you choose from a split list
(skill and/or cron per scheduler). For each cron scheduler you can customise the run
time and (for daily schedulers) the minimum session length thresholds — press Enter to
accept the defaults. It also handles uninstall, grouped by mechanism.

Each scheduler can also be installed standalone from its own folder
(`cd <scheduler> && ./install.ps1` / `bash install.sh`, optional `skill` / `cron`
mode argument). Open a new terminal afterwards so `C4_CLAUDE_META_DIR` is live in your shell.

## Requirements

| Platform | Requirements |
|----------|-------------|
| Windows  | PowerShell 5+, `claude` CLI on PATH, `git` on PATH |
| Linux    | Bash 4+, `claude` CLI on PATH, `git` on PATH, `jq` on PATH |

## Configuration

| Variable | Purpose |
|----------|---------|
| `C4_CLAUDE_META_DIR` | Location of the `claude-meta` output repo (default `~/claude-meta`). |

---

## daily-summary

Runs at 02:00 every day. Scans `~/.claude/projects/**/*.jsonl` for chat files
modified since the last run (cutoff = write time of the most recently created summary
file; first run processes all history).

For each new chat it:

1. Reads the `.jsonl` line by line and reconstructs the conversation as `[USER]` /
   `[ASSISTANT]` turns. Assistant blocks are capped at 2000 chars to prevent large
   code dumps from overflowing Claude's context.
2. Applies a short-session filter — skips if fewer than 2 user turns or fewer than
   500 total characters.
3. Writes a temporary `chat-input.md` with session metadata and the transcript.
4. Invokes `claude --print <prompt>` using `daily-summary.md` as the prompt.
5. Deletes `chat-input.md`.

After all chats are processed, calls `git-sync` to commit and push. Chats whose
output file already exists are skipped.

**Interactive skill (no programmatic credit):** run `/session-digest-daily-summary` from
a Claude Code session opened in the meta repo. It runs `daily-summary-prepare.{sh,ps1}`
(same scan/filter logic, but stages one input file per chat plus a `manifest.json` under
`$C4_CLAUDE_META_DIR/.claude/scheduler-jobs/daily-summary/`, gitignored), spawns one
subagent per chat to write each summary, then runs `git-sync` once.

### Output

One `.md` file per summarised chat session, organised by year and month:

```
$C4_CLAUDE_META_DIR/
  daily-summaries/
    2026/
      04/
        2026-04-07_2c042fa6-92b0-4d92-a61e-78ab74936f85_260406-cc-scheduler.md
        2026-04-07_5099494e-cf24-4819-9bf5-1511712d8300.md
```

Filename: `<date>_<uuid>_<title>.md` when the session has a custom title, `<date>_<uuid>.md`
otherwise. Characters invalid in filenames are replaced with `-`; spaces with `_`.

Each file contains the headings `## What was worked on`, `## Current State`,
`## Decisions made`, `## Pending / Next Steps`, `## Key Facts for Next Session`,
`## Outcomes`, `## Open items`. Sections with no content are omitted; very short sessions
get a single `## Note: No significant work recorded.` instead.

### Run manually

```powershell
# Windows — only new sessions (default), or -FullScan to reprocess all
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-summary-trigger.ps1"
```

```bash
# Linux — only new sessions (default), or --full-scan to reprocess all
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-summary-trigger.sh"
```

---

## daily-lessons

Nightly scheduler that scans Claude Code session histories and extracts lessons learned
from each session using the `ceh-lessons-learned` marketplace skill. One file is produced
per session and committed to `lessons-learned/` in your `claude-meta` repo, organised by
year and month.

1. At **03:00** the trigger scans `~/.claude/projects/**/*.jsonl` for chat files
   modified since the last run.
2. Each file is compared against existing output in `lessons-learned/` — already
   processed sessions are skipped (matched by UUID in filename).
3. The transcript is extracted and written to a temporary input file.
4. Claude is invoked with a prompt that calls the `/ceh-lessons-learned:lessons-learned`
   skill on the transcript.
5. The skill writes lessons to `docs/claude_logs/LESSONS_LEARNED.md` (a transient
   staging path, gitignored). The trigger immediately moves the file to its final
   named location.
6. Sessions that yield no lessons receive a stub file so they are not retried.
7. After all sessions are processed, a single `git-sync` commit is made.

Scheduled one hour after `daily-summary` (02:00) to avoid concurrent `git-sync` conflicts
on the same meta repo.

**Interactive skill (no programmatic credit):** run `/session-digest-daily-lessons` from
a Claude Code session opened in the meta repo. It stages inputs via
`daily-lessons-prepare.{sh,ps1}` under `.claude/scheduler-jobs/daily-lessons/`
(gitignored), spawns one subagent per chat to extract lessons (or write a stub), then runs
`git-sync` once. Unlike the cron trigger it does **not** call the `ceh-lessons-learned`
marketplace skill (its fixed output path would collide across parallel subagents); the
extraction methodology is embedded in the skill instead.

### Output

```
lessons-learned/
  2026/
    04/
      2026-04-18_<uuid>_<session-title>.md   <- real lessons
      2026-04-19_<uuid>.md                   <- session had no custom title
      2026-04-20_<uuid>_<title>.md           <- stub if no lessons found
```

Filename format `<date>_<uuid>[_<safe-title>].md`: `date` is YYYY-MM-DD from the JSONL
file's mtime, `uuid` is the JSONL basename, `safe-title` is the session title with spaces
→ `_` and forbidden chars removed (omitted if no custom title).

### Filters

Sessions are skipped without producing output if the UUID is already in `lessons-learned/`
(already processed), there are 0 messages after cutoff, fewer than 2 user turns, or under
500 chars of transcript. Sessions skipped because already-processed produce **no file**;
sessions that pass filtering but yield no lessons produce a **stub file**, so the UUID is
recorded and not retried.

### Run manually

```bash
# Linux — only new sessions (default), or --full-scan to reprocess all
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-lessons-trigger.sh"
```

```powershell
# Windows — only new sessions (default), or -FullScan to reprocess all
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-lessons-trigger.ps1"
```

> **Prerequisite (cron mechanism only):** the `ceh-lessons-learned` skill must be installed
> from the [agent-skills marketplace](https://github.com/cheneeheng/agent-skills). The
> interactive skill embeds its own methodology and does not need it.

---

## weekly-lessons

Runs at 02:00 every Sunday. Scans `$C4_CLAUDE_META_DIR/lessons-learned/**/*.md` — the
per-session files written by `daily-lessons` — for files newer than the last harvest.
Stub files (sessions that produced no lessons) are skipped automatically.

All collected content is passed to Claude via `claude --print <prompt>`. Claude filters
for project-generic lessons only (domain-specific lessons are discarded), deduplicates
against the existing master file, appends new lessons under the appropriate category
heading, and creates `MASTER_LESSONS_LEARNED.md` on first run. After Claude finishes the
input file is deleted and `git-sync` is called.

**Time filtering:** after each successful run a cursor file
(`$C4_CLAUDE_META_DIR/.claude/weekly-lessons-cursor`) records the mtime of the newest
session file processed. Only files newer than the cursor are picked up next time. The
cursor is written only after Claude exits successfully, so a crash retries the same files.

**Interactive skill (no programmatic credit):** run `/session-digest-weekly-lessons` from
a Claude Code session opened in the meta repo. Unlike the daily skills it uses **no
subagents** — a single analysis pass. `weekly-lessons-prepare.{sh,ps1}` collects the new
session lessons into one input file under `.claude/scheduler-jobs/weekly-lessons/`
(gitignored) and prints the input/cursor/master paths plus the epoch to advance the cursor
to; the session distils into the master, writes the cursor, then runs `git-sync`.

### Output

A single cumulative file, appended to on each Sunday run:

```
$C4_CLAUDE_META_DIR/
  master-lessons/
    MASTER_LESSONS_LEARNED.md
```

Lessons are grouped under category headings: `Architecture`, `Debugging`, `Performance`,
`Security`, `Testing`, `Tooling`, `Workflow`, `API behaviour`, `Database`, `Other`. Each
entry carries a short title, `**Source**`, `**Lesson**`, `**Apply when**`, and `**Tags**`.

### Run manually

```powershell
# Windows — only new sessions (default), or -FullScan to reprocess all
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\weekly-lessons-trigger.ps1"
```

```bash
# Linux — only new sessions (default), or --full-scan to reprocess all
bash "$C4_CLAUDE_META_DIR/.claude/scripts/weekly-lessons-trigger.sh"
```

---

## git-sync

A pure shell utility — no LLM involved. Called by `daily-summary`, `daily-lessons`, and
`weekly-lessons` after Claude has written its output files.

1. `git add -A` in `claude-meta`.
2. Commits with message `<label>: <timestamp>` (e.g. `daily-summary: 2026-04-07 02:03`).
3. Pushes if a remote is configured; logs a note and exits cleanly if not.

It is copied automatically by any scheduler's installer; to install standalone run
`cd git-sync && ./install.ps1` (Windows) / `bash install.sh` (Linux).

### Add a remote

```bash
cd "$C4_CLAUDE_META_DIR"
git remote add origin <your-remote-url>
git push -u origin main
```

### claude-meta structure

All schedulers write to `$C4_CLAUDE_META_DIR` (default: `~/claude-meta`):

```
claude-meta/
  daily-summaries/     <- one .md per chat session (daily-summary)
  lessons-learned/     <- one .md per chat session (daily-lessons)
  master-lessons/      <- MASTER_LESSONS_LEARNED.md (weekly-lessons)
  logs/                <- trigger output logs (Linux only)
  .claude/
    scripts/           <- trigger + prepare scripts, prompts, and git-sync
    skills/            <- interactive scheduler skills (skill mechanism)
    scheduler-jobs/    <- transient prepare staging (gitignored)
    settings.json      <- Claude tool permissions for unattended runs
    scheduled-repos.json  <- local repo list for weekly-lessons
```

---

## Uninstall

```powershell
# Windows
.\setup.ps1   # choose [2] Uninstall
```

```bash
# Linux
bash setup.sh   # choose [2] Uninstall
```

See [CHANGELOG.md](CHANGELOG.md) for release history.
