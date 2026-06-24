# weekly-lessons

Runs at 02:00 every Sunday. Scans `$CLAUDE_META_DIR/lessons-learned/**/*.md` — the
per-session files written by `daily-lessons` — for files newer than the last harvest.
Stub files (sessions that produced no lessons) are skipped automatically.

All collected content is passed to Claude via `claude --print <prompt>`. Claude:

- Filters for project-generic lessons only (domain-specific lessons are discarded).
- Deduplicates against the existing master file.
- Appends new lessons under the appropriate category heading.
- Creates `MASTER_LESSONS_LEARNED.md` on first run if it does not yet exist.

After Claude finishes, the input file is deleted and `git-sync` is called.

**Time filtering**: after each successful run a cursor file
(`$CLAUDE_META_DIR/.claude/weekly-lessons-cursor`) records the mtime of the newest
session file processed. Only files newer than the cursor are picked up next time.
The cursor is written only after Claude exits successfully, so a crash retries the
same files on the next run.

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic credit.
As an alternative, run the harvest from inside a Claude Code session with the
`/claude-code-scheduler-weekly-lessons` skill (installed to
`$CLAUDE_META_DIR/.claude/skills/`). No `claude --print` is used, and — unlike the
daily skills — no subagents: it is a single analysis pass.

1. Runs `weekly-lessons-prepare.{sh,ps1}` — the same cursor / stub-skip logic as the
   trigger; it collects the new session lessons into one input file under
   `$CLAUDE_META_DIR/.claude/scheduler-jobs/weekly-lessons/` (gitignored) and prints the
   input path, cursor path, master path, and the epoch to advance the cursor to.
2. The session reads the input and the master file, distils the project-generic lessons
   into the master, writes the cursor, then runs `git-sync`.

Run it from a Claude Code session opened in the meta repo:

```
/claude-code-scheduler-weekly-lessons
```

---

## Install

```powershell
# Windows — both mechanisms (default); or -Mode skill / -Mode cron
cd weekly-lessons
.\install.ps1
```

```bash
# Linux — both mechanisms (default); or: bash install.sh skill | cron
cd weekly-lessons
bash install.sh
```

Or run the repo-root `setup.{sh,ps1}` to pick schedulers and mechanisms interactively.

### What gets installed

Which files are installed depends on the chosen mode (`skill` / `cron` / `both`).

| File | Mechanism | Destination |
|------|-----------|-------------|
| `weekly-lessons.md` | cron | `$CLAUDE_META_DIR/.claude/scripts/` |
| `weekly-lessons-trigger.ps1` / `.sh` | cron | `$CLAUDE_META_DIR/.claude/scripts/` |
| `weekly-lessons-prepare.ps1` / `.sh` | skill | `$CLAUDE_META_DIR/.claude/scripts/` |
| `claude-code-scheduler-weekly-lessons/SKILL.md` | skill | `$CLAUDE_META_DIR/.claude/skills/` |
| `git-sync.ps1` / `.sh` | both | `$CLAUDE_META_DIR/.claude/scripts/` |
| Cursor file (written at runtime) | both | `$CLAUDE_META_DIR/.claude/weekly-lessons-cursor` |
| Scheduled task | cron | `ClaudeCode-WeeklyLessons` (Windows) / crontab entry (Linux) |
| Git repo | both | `$CLAUDE_META_DIR` (initialised if absent) |
| Env file (Linux only) | both | `~/.claude/claude-scheduler.env` |

---

## Output

A single cumulative file, appended to on each Sunday run:

```
$CLAUDE_META_DIR/
  master-lessons/
    MASTER_LESSONS_LEARNED.md
```

Lessons are grouped under category headings: `Architecture`, `Debugging`, `Performance`,
`Security`, `Testing`, `Tooling`, `Workflow`, `API behaviour`, `Database`, `Other`.
Each entry:

```markdown
### [Short descriptive title]
**Source**: <session-filename> (YYYY-MM-DD)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
```

---

## Run manually

```powershell
# Windows — process only new sessions (default)
& "$env:CLAUDE_META_DIR\.claude\scripts\weekly-lessons-trigger.ps1"

# Windows — reprocess all session lessons from the beginning
& "$env:CLAUDE_META_DIR\.claude\scripts\weekly-lessons-trigger.ps1" -FullScan
```

```bash
# Linux — process only new sessions (default)
bash "$CLAUDE_META_DIR/.claude/scripts/weekly-lessons-trigger.sh"

# Linux — reprocess all session lessons from the beginning
bash "$CLAUDE_META_DIR/.claude/scripts/weekly-lessons-trigger.sh" --full-scan
```
