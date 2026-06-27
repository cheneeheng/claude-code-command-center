# daily-summary

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

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic credit.
As an alternative, run the same job from inside a Claude Code session with the
`/session-digest-daily-summary` skill (installed to
`$C4_CLAUDE_META_DIR/.claude/skills/`). It is a coordinator and uses no `claude --print`:

1. Runs `daily-summary-prepare.{sh,ps1}` — the same scan / filter logic as the trigger,
   but instead of calling Claude it stages one input file per new chat plus a
   `manifest.json` under `$C4_CLAUDE_META_DIR/.claude/scheduler-jobs/daily-summary/`
   (gitignored).
2. Spawns one subagent per chat (in batches) to write each summary file directly.
3. Runs `git-sync` once at the end.

Run it from a Claude Code session opened in the meta repo:

```
/session-digest-daily-summary
```

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

Open a new terminal afterwards so `C4_CLAUDE_META_DIR` is live in your shell. Or run the
repo-root `setup.{sh,ps1}` to pick schedulers and mechanisms interactively.

### What gets installed

Which files are installed depends on the chosen mode (`skill` / `cron` / `both`).

| File | Mechanism | Destination |
|------|-----------|-------------|
| `daily-summary.md` | cron | `$C4_CLAUDE_META_DIR/.claude/scripts/` |
| `daily-summary-trigger.ps1` / `.sh` | cron | `$C4_CLAUDE_META_DIR/.claude/scripts/` |
| `daily-summary-prepare.ps1` / `.sh` | skill | `$C4_CLAUDE_META_DIR/.claude/scripts/` |
| `session-digest-daily-summary/SKILL.md` | skill | `$C4_CLAUDE_META_DIR/.claude/skills/` |
| `git-sync.ps1` / `.sh` | both | `$C4_CLAUDE_META_DIR/.claude/scripts/` |
| Scheduled task | cron | `SessionDigest-DailySummary` (Windows) / crontab entry (Linux) |
| Git repo | both | `$C4_CLAUDE_META_DIR` (initialised if absent) |
| Env file (Linux only) | both | `~/.claude/claude-scheduler.env` |

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

Filename: `<date>_<uuid>_<title>.md` when the session has a custom title, `<date>_<uuid>.md`
otherwise. Characters invalid in filenames are replaced with `-`; spaces with `_`.

Each file contains:

```markdown
# Chat Summary — YYYY-MM-DD
**Session**: <uuid>
**Title**: <custom title or uuid>
**Project**: <directory name of the working directory>

## What was worked on
## Current State
## Decisions made
## Pending / Next Steps
## Key Facts for Next Session
## Outcomes
## Open items
```

Sections with no content are omitted. Very short sessions get a single
`## Note: No significant work recorded.` instead.

---

## Run manually

```powershell
# Windows — process only new sessions (default)
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-summary-trigger.ps1"

# Windows — reprocess all sessions from the beginning
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-summary-trigger.ps1" -FullScan
```

```bash
# Linux — process only new sessions (default)
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-summary-trigger.sh"

# Linux — reprocess all sessions from the beginning
bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-summary-trigger.sh" --full-scan
```
