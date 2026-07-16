# daily-lessons

Nightly scheduler that scans Claude Code session histories and extracts lessons
learned — corrections, failed commands, wrong assumptions — from each session.
One file is produced per session and committed to the `lessons-learned/` folder
of your `claude-meta` repo, organised by year and month.

---

## How it works

1. At **03:00** (one hour after `daily-summary`, to avoid concurrent `git-sync`
   commits) the trigger runs the shared prepare script
   (`daily-digest-prepare.{ps1,sh} daily-lessons`), which scans
   `~/.claude/projects/**/*.jsonl` (and `~/.claude_devcontainer`) for chat files
   modified since the cursor (`.claude/daily-lessons-cursor`).
2. Each new chat is filtered (see [Filters](#filters)), then staged as an input
   file plus a `manifest.json` entry under
   `.claude/scheduled-session-digests/daily-lessons/` (gitignored).
3. The trigger feeds each staged job to `claude --model sonnet --effort medium
   --print`, with the job's input/output paths substituted into the
   `daily-lessons.md` prompt. Claude writes the lessons file directly to its
   final path — or a stub (`_No lessons extracted from this session._`) so the
   session is marked processed and not retried.
4. The cursor advances over each verified output (oldest-first), so a crash or
   failed chat is retried on exactly the next run.
5. After all chats are processed, one `git-sync` commit is made and the staging
   directory is deleted.

The extraction methodology is embedded in the prompt (and in the skill below) —
no external skill dependency.

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic
credit. As an alternative, run the same job from inside a Claude Code session
with the `/session-digest-daily-lessons` skill (installed to
`$C4_CLAUDE_META_DIR/.claude/skills/`). It is a coordinator and uses no
`claude --print`:

1. Runs the same prepare script, staging the same inputs and manifest.
2. Spawns one subagent per chat (in batches of 5) to extract lessons and write
   each output file (or the stub) directly.
3. Advances the cursor, runs `git-sync` once, and cleans up the staging dir.

Run it from a Claude Code session opened in the meta repo:

```
/session-digest-daily-lessons
```

---

## Output

```
lessons-learned/
  2026/
    04/
      2026-04-18_<uuid>_<session-title>.md   <- real lessons
      2026-04-19_<uuid>.md                   <- session had no custom title
      2026-04-20_<uuid>_<title>.md           <- stub if no lessons found
```

Filename: `<date>_<uuid>_<safe-title>.md` when the session has a custom title,
`<date>_<uuid>.md` otherwise (`date` from the chat file's mtime, invalid filename
characters and spaces replaced with `_`).

Each file contains a `# Lessons` header block plus one `## <date> — <title>`
entry per lesson (**What happened** / **Lesson**). Sessions that pass the
filters but yield no lessons get the stub body instead, so the UUID is recorded
and the session is not retried. The stub files are skipped by `weekly-lessons`.

---

## Filters

Sessions are skipped without producing output if:

| Condition | Reason |
|---|---|
| UUID already in `lessons-learned/` | Already processed |
| 0 messages after cutoff | No new content since last run |
| < 2 user turns | Single-message exchanges, accidental opens |
| < 500 chars of transcript | Too short to contain meaningful lessons |

The turn/length thresholds are configurable at install
(`scheduler-config.json`). Skipped sessions still advance the cursor, so they
are not rescanned every run.

---

## Install

```powershell
# Windows — both mechanisms (default); or -Mode skill / -Mode cron
cd daily-lessons
.\install.ps1
```

```bash
# Linux — both mechanisms (default); or: bash install.sh skill | cron
cd daily-lessons
bash install.sh
```

Open a new terminal afterwards so `C4_CLAUDE_META_DIR` is live in your shell. Or
run the member-root `setup.{sh,ps1}` to pick schedulers and mechanisms
interactively.

### Files installed into claude-meta

Which files are installed depends on the chosen mode (`skill` / `cron` / `both`).

| Path | Mechanism | Purpose |
|---|---|---|
| `.claude/scripts/daily-digest-prepare.ps1` / `.sh` | both | Shared scan/stage logic |
| `.claude/scripts/daily-lessons.md` | cron | Claude prompt template |
| `.claude/scripts/daily-digest-trigger.ps1` / `.sh` | cron | Trigger (`claude --print`) |
| `.claude/skills/session-digest-daily-lessons/SKILL.md` | skill | Interactive coordinator skill |
| `.claude/scripts/git-sync.ps1` / `.sh` | both | Shared commit helper |
| Scheduled task / cron entry | cron | `SessionDigest-DailyLessons` (Windows) / crontab line (Linux) |

At runtime the scheduler also maintains `.claude/daily-lessons-cursor` (progress
cursor) and the transient `.claude/scheduled-session-digests/daily-lessons/`
staging dir (gitignored, auto-cleaned).

---

## Manual run

```powershell
# Windows — process only new sessions (default)
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-digest-trigger.ps1" -Scheduler daily-lessons

# Windows — reprocess all sessions from the beginning
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-digest-trigger.ps1" -Scheduler daily-lessons -FullScan
```

```bash
# Linux — process only new sessions (default)
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-digest-trigger.sh" daily-lessons

# Linux — reprocess all sessions from the beginning
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-digest-trigger.sh" daily-lessons --full-scan
```

---

## Relationship to other schedulers

| Scheduler | Time | Output |
|---|---|---|
| `daily-summary` | 02:00 | `daily-summaries/YYYY/MM/` — conversation summaries |
| `daily-lessons` | 03:00 | `lessons-learned/YYYY/MM/` — extracted lessons |
| `weekly-lessons` | Sun 02:00 | `master-lessons/` — cross-project lesson harvest |

`weekly-lessons` consumes this scheduler's output.
