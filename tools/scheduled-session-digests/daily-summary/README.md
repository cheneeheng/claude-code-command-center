# daily-summary

Nightly scheduler that scans Claude Code session histories and writes one concise
summary per session, committed to the `daily-summaries/` folder of your
`claude-meta` repo, organised by year and month.

---

## How it works

1. At **02:00** the trigger runs the shared prepare script
   (`daily-digest-prepare.{ps1,sh} daily-summary`), which scans
   `~/.claude/projects/**/*.jsonl` (and `~/.claude_devcontainer`) for chat files
   modified since the cursor (`.claude/daily-summary-cursor`).
2. Each new chat is filtered (see [Filters](#filters)), then staged as an input
   file plus a `manifest.json` entry under
   `.claude/scheduled-session-digests/daily-summary/` (gitignored).
3. The trigger feeds each staged job to `claude --model haiku --print`, with the
   job's input/output paths substituted into the `daily-summary.md` prompt.
   Claude writes the summary directly to its final path.
4. The cursor advances over each verified output (oldest-first), so a crash or
   failed chat is retried on exactly the next run.
5. After all chats are processed, one `git-sync` commit is made and the staging
   directory is deleted.

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic
credit. As an alternative, run the same job from inside a Claude Code session
with the `/session-digest-daily-summary` skill (installed to
`$C4_CLAUDE_META_DIR/.claude/skills/`). It is a coordinator and uses no
`claude --print`:

1. Runs the same prepare script, staging the same inputs and manifest.
2. Spawns one subagent per chat (in batches of 5) to write each summary directly.
3. Advances the cursor, runs `git-sync` once, and cleans up the staging dir.

Run it from a Claude Code session opened in the meta repo:

```
/session-digest-daily-summary
```

---

## Output

One `.md` file per summarised chat session, organised by year and month:

```
$C4_CLAUDE_META_DIR/
  daily-summaries/
    2026/
      04/
        2026-04-07_2c042fa6-92b0-4d92-a61e-78ab74936f85_260406-cc-scheduler.md
        2026-04-07_5099494e-cf24-4819-9bf5-1511712d8300.md
```

Filename: `<date>_<uuid>_<safe-title>.md` when the session has a custom title,
`<date>_<uuid>.md` otherwise (`date` from the chat file's mtime, invalid filename
characters and spaces replaced with `_`).

Each file contains a `# Chat Summary` header block plus these sections (empty
sections are omitted): What was worked on · Decisions made · Outcomes · Current
State · Pending / Next Steps · Key Facts for Next Session · Open items. Very
short sessions get a single `## Note: No significant work recorded.` instead.

---

## Filters

Sessions are skipped without producing output if:

| Condition | Reason |
|---|---|
| UUID already in `daily-summaries/` | Already summarised |
| 0 messages after cutoff | No new content since last run |
| < 2 user turns | Single-message exchanges, accidental opens |
| < 500 chars of transcript | Too short to be worth summarising |

The turn/length thresholds are configurable at install
(`scheduler-config.json`). Skipped sessions still advance the cursor, so they
are not rescanned every run.

---

## Install

```powershell
# Windows — both mechanisms (default); or -Mode skill / -Mode cron
cd daily-summary
.\install.ps1
```

```bash
# Linux — both mechanisms (default); or: bash install.sh skill | cron
cd daily-summary
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
| `.claude/scripts/daily-summary.md` | cron | Claude prompt template |
| `.claude/scripts/daily-digest-trigger.ps1` / `.sh` | cron | Trigger (`claude --print`) |
| `.claude/skills/session-digest-daily-summary/SKILL.md` | skill | Interactive coordinator skill |
| `.claude/scripts/git-sync.ps1` / `.sh` | both | Shared commit helper |
| Scheduled task / cron entry | cron | `SessionDigest-DailySummary` (Windows) / crontab line (Linux) |

At runtime the scheduler also maintains `.claude/daily-summary-cursor` (progress
cursor) and the transient `.claude/scheduled-session-digests/daily-summary/`
staging dir (gitignored, auto-cleaned).

---

## Manual run

```powershell
# Windows — process only new sessions (default)
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-digest-trigger.ps1" -Scheduler daily-summary

# Windows — reprocess all sessions from the beginning
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-digest-trigger.ps1" -Scheduler daily-summary -FullScan
```

```bash
# Linux — process only new sessions (default)
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-digest-trigger.sh" daily-summary

# Linux — reprocess all sessions from the beginning
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-digest-trigger.sh" daily-summary --full-scan
```

---

## Relationship to other schedulers

| Scheduler | Time | Output |
|---|---|---|
| `daily-summary` | 02:00 | `daily-summaries/YYYY/MM/` — conversation summaries |
| `daily-lessons` | 03:00 | `lessons-learned/YYYY/MM/` — extracted lessons |
| `weekly-lessons` | Sun 02:00 | `master-lessons/` — cross-project lesson harvest |

daily-lessons is staggered an hour later to avoid concurrent `git-sync` commits
on the same meta repo.
