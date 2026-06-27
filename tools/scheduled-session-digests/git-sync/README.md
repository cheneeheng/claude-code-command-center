# git-sync

A pure shell utility — no LLM involved. Called by `daily-summary`, `daily-lessons`,
and `weekly-lessons` after Claude has written its output files.

1. `git add -A` in `claude-meta`.
2. Commits with message `<label>: <timestamp>` (e.g. `daily-summary: 2026-04-07 02:03`).
3. Pushes if a remote is configured; logs a note and exits cleanly if not.

---

## Install

`git-sync` is copied automatically by any scheduler's installer (`daily-summary`,
`daily-lessons`, or `weekly-lessons`). To install it standalone:

```powershell
# Windows
cd git-sync
.\install.ps1
```

```bash
# Linux
cd git-sync
bash install.sh
```

---

## Add a remote

```bash
cd "$C4_CLAUDE_META_DIR"
git remote add origin <your-remote-url>
git push -u origin main
```

---

## claude-meta structure

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
