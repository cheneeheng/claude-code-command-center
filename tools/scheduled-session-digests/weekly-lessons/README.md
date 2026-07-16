# weekly-lessons

Weekly scheduler that harvests the per-session lessons files written by
`daily-lessons`, distils the project-generic ones, and appends them to a single
cumulative master file in your `claude-meta` repo.

---

## How it works

1. Every **Sunday at 02:00** the trigger runs the prepare script
   (`weekly-lessons-prepare.{ps1,sh}`), which scans
   `lessons-learned/**/*.md` for files newer than the cursor
   (`.claude/weekly-lessons-cursor`), skipping "no lessons" stub files.
2. The collected content is staged as `input.md` plus a `manifest.json` under
   `.claude/scheduled-session-digests/weekly-lessons/` (gitignored).
3. The trigger runs `claude --model opus --effort high --print` with the input
   and master paths substituted into the `weekly-lessons.md` prompt. Claude
   filters for project-generic lessons, deduplicates against the existing master
   file, and appends new lessons under category headings (creating
   `MASTER_LESSONS_LEARNED.md` on first run).
4. Only after Claude exits successfully is the cursor advanced to the newest
   harvested file's mtime — a crash retries the same files next run.
5. `git-sync` makes one commit and the staging directory is deleted.

---

## Interactive skill (no programmatic credit)

The cron trigger above calls `claude --print`, which consumes programmatic
credit. As an alternative, run the harvest from inside a Claude Code session
with the `/session-digest-weekly-lessons` skill (installed to
`$C4_CLAUDE_META_DIR/.claude/skills/`). No `claude --print` is used, and —
unlike the daily skills — no subagents: it is a single analysis pass.

1. Runs the same prepare script, staging the same input and manifest.
2. The session reads the input and the master file, distils the project-generic
   lessons into the master, advances the cursor, runs `git-sync`, and cleans up
   the staging dir.

Run it from a Claude Code session opened in the meta repo:

```
/session-digest-weekly-lessons
```

---

## Output

A single cumulative file, appended to on each run:

```
$C4_CLAUDE_META_DIR/
  master-lessons/
    MASTER_LESSONS_LEARNED.md
```

Lessons are grouped under category headings: `Architecture`, `Debugging`,
`Performance`, `Security`, `Testing`, `Tooling`, `Workflow`, `API behaviour`,
`Database`, `Other`. Each entry:

```markdown
### [Short descriptive title]
**Source**: <session-filename> (YYYY-MM-DD)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
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

Requires `daily-lessons` to have run at least once to populate
`lessons-learned/`. Or run the member-root `setup.{sh,ps1}` to pick schedulers
and mechanisms interactively.

### Files installed into claude-meta

Which files are installed depends on the chosen mode (`skill` / `cron` / `both`).

| Path | Mechanism | Purpose |
|---|---|---|
| `.claude/scripts/weekly-lessons-prepare.ps1` / `.sh` | both | Scan/collect logic |
| `.claude/scripts/weekly-lessons.md` | cron | Claude prompt template |
| `.claude/scripts/weekly-lessons-trigger.ps1` / `.sh` | cron | Trigger (`claude --print`) |
| `.claude/skills/session-digest-weekly-lessons/SKILL.md` | skill | Interactive harvest skill |
| `.claude/scripts/git-sync.ps1` / `.sh` | both | Shared commit helper |
| `.claude/settings.json` | both | Claude tool permissions for unattended runs |
| Scheduled task / cron entry | cron | `SessionDigest-WeeklyLessons` (Windows) / crontab line (Linux) |

At runtime the scheduler also maintains `.claude/weekly-lessons-cursor`
(progress cursor) and the transient
`.claude/scheduled-session-digests/weekly-lessons/` staging dir (gitignored,
auto-cleaned).

---

## Manual run

```powershell
# Windows — process only new lessons files (default)
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\weekly-lessons-trigger.ps1"

# Windows — reprocess all lessons files from the beginning
& "$env:C4_CLAUDE_META_DIR\.claude\scripts\weekly-lessons-trigger.ps1" -FullScan
```

```bash
# Linux — process only new lessons files (default)
bash "$C4_CLAUDE_META_DIR/.claude/scripts/weekly-lessons-trigger.sh"

# Linux — reprocess all lessons files from the beginning
bash "$C4_CLAUDE_META_DIR/.claude/scripts/weekly-lessons-trigger.sh" --full-scan
```

---

## Relationship to other schedulers

| Scheduler | Time | Output |
|---|---|---|
| `daily-summary` | 02:00 | `daily-summaries/YYYY/MM/` — conversation summaries |
| `daily-lessons` | 03:00 | `lessons-learned/YYYY/MM/` — extracted lessons (this scheduler's input) |
| `weekly-lessons` | Sun 02:00 | `master-lessons/` — cross-project lesson harvest |
