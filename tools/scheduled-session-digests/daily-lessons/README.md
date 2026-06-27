# daily-lessons

Nightly scheduler that scans Claude Code session histories and extracts lessons
learned from each session using the `ceh-lessons-learned` marketplace skill.

One file is produced per session and committed to the `lessons-learned/` folder
in your `claude-meta` repo, organised by year and month.

---

## How it works

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

**Schedule**: 03:00 daily — one hour after `daily-summary` (02:00) to avoid
concurrent `git-sync` conflicts on the same meta repo.

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic credit.
As an alternative you can run the same job from inside a Claude Code session with the
`/session-digest-daily-lessons` skill (installed to
`$C4_CLAUDE_META_DIR/.claude/skills/`).

The skill is a coordinator and uses no `claude --print`:

1. Runs `daily-lessons-prepare.{sh,ps1}` — the same scan / filter logic as the trigger,
   but instead of calling Claude it stages one input file per new chat plus a
   `manifest.json` under `$C4_CLAUDE_META_DIR/.claude/scheduler-jobs/daily-lessons/`
   (gitignored).
2. Spawns one subagent per chat (in batches) to extract lessons and write each output
   file (or a stub if none) directly.
3. Runs `git-sync` once at the end.

Run it from a Claude Code session opened in the meta repo:

```
/session-digest-daily-lessons
```

> Unlike the cron trigger, the skill does not call the `ceh-lessons-learned` marketplace
> skill (its fixed output path would collide across parallel subagents); the extraction
> methodology is embedded in the skill instead.

---

## Output

```
lessons-learned/
  2026/
    04/
      2026-04-18_<uuid>_<session-title>.md   ← real lessons
      2026-04-19_<uuid>.md                   ← session had no custom title
      2026-04-20_<uuid>_<title>.md           ← stub if no lessons found
```

### Filename format

```
<date>_<uuid>[_<safe-title>].md
```

- `date` — YYYY-MM-DD derived from the JSONL file's last-modified timestamp
- `uuid` — Claude session identifier (the JSONL basename)
- `safe-title` — session title with spaces → `_` and forbidden chars removed;
  omitted if no custom title was set

---

## Filters

Sessions are skipped without producing output if:

| Condition | Reason |
|---|---|
| UUID already in `lessons-learned/` | Already processed |
| 0 messages after cutoff | No new content since last run |
| < 2 user turns | Single-message exchanges, accidental opens |
| < 500 chars of transcript | Too short to contain meaningful lessons |

Sessions skipped by the first filter produce **no file**. Sessions that pass
filtering but yield no lessons from the skill produce a **stub file**, so the
UUID is recorded and the session is not retried.

---

## Install

### Linux / macOS

```bash
cd daily-lessons
bash install.sh          # both mechanisms (default)
bash install.sh skill    # interactive skill only (no cron, no claude -p)
bash install.sh cron     # cron trigger only
```

Registers a cron job at 03:00 daily. Logs to `$C4_CLAUDE_META_DIR/logs/daily-lessons.log`.

### Windows

```powershell
cd daily-lessons
.\install.ps1                # both mechanisms (default)
.\install.ps1 -Mode skill   # interactive skill only
.\install.ps1 -Mode cron    # cron trigger only
```

Registers a Windows Task Scheduler task (`SessionDigest-DailyLessons`) at 03:00 daily.
Logs to `%C4_CLAUDE_META_DIR%\logs\daily-lessons.log`.

Or run the repo-root `setup.{sh,ps1}` to pick schedulers and mechanisms interactively.

> **Prerequisite (cron mechanism only)**: `ceh-lessons-learned` skill must be installed
> from the [agent-skills marketplace](https://github.com/cheneeheng/agent-skills). The
> interactive skill embeds its own methodology and does not need it.

---

## Manual run

```bash
# Process only new sessions (default)
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-lessons-trigger.sh"

# Reprocess all sessions from the beginning
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-lessons-trigger.sh" --full-scan
```

```powershell
# Process only new sessions (default)
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-lessons-trigger.ps1"

# Reprocess all sessions from the beginning
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-lessons-trigger.ps1" -FullScan
```

---

## Files installed into claude-meta

Which files are installed depends on the chosen mode (`skill` / `cron` / `both`).

| Path | Mechanism | Purpose |
|---|---|---|
| `.claude/scripts/daily-lessons.md` | cron | Claude prompt |
| `.claude/scripts/daily-lessons-trigger.sh` / `.ps1` | cron | Trigger (`claude --print`) |
| `.claude/scripts/daily-lessons-prepare.sh` / `.ps1` | skill | Stages inputs + manifest |
| `.claude/skills/session-digest-daily-lessons/SKILL.md` | skill | Interactive coordinator skill |
| `.claude/scripts/git-sync.sh` / `git-sync.ps1` | both | Shared commit helper |
| `.claude/scheduler-jobs/daily-lessons/` | skill | Transient staging (gitignored) |
| `lessons-learned/` | both | Output directory (year/month subdirs) |
| `docs/claude_logs/` | cron | Transient staging area (gitignored) |

---

## Relationship to other schedulers

| Scheduler | Time | Output |
|---|---|---|
| `daily-summary` | 02:00 | `daily-summaries/YYYY/MM/` — conversation summaries |
| `daily-lessons` | 03:00 | `lessons-learned/YYYY/MM/` — extracted lessons |
| `weekly-lessons` | Sun 02:00 | `master-lessons/` — cross-repo lesson harvest |
