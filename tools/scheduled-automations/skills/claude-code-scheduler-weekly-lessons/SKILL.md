---
name: claude-code-scheduler-weekly-lessons
description: Run the weekly-lessons harvest from inside an interactive Claude Code session instead of via the cron/Task Scheduler trigger (which calls `claude --print` and burns programmatic credit). Use when the user asks to "run weekly lessons", "harvest lessons", or "update the master lessons file". The prepare script collects the week's per-session lessons; you distil the project-generic ones into the master file directly, advance the cursor, then git-sync. No subagents are needed — this is a single analysis job.
---

# Weekly Lessons — interactive harvest

The prepare script collects every per-session lessons file written since the last
harvest into one input file. You read it, distil the project-generic lessons into
the master file, advance the cursor, and commit. No `claude --print` is used.

## Step 1 — Run the prepare script

`CLAUDE_META_DIR` must be set (the scheduler's `~/.claude/claude-scheduler.env`
sets it; the prepare script also sources that file). Scripts are installed at
`$CLAUDE_META_DIR/.claude/scripts/`.

Run the script for the current OS and capture stdout:

- Windows (PowerShell tool):
  `& "$env:CLAUDE_META_DIR\.claude\scripts\weekly-lessons-prepare.ps1"`
- macOS / Linux (Bash tool):
  `bash "$CLAUDE_META_DIR/.claude/scripts/weekly-lessons-prepare.sh"`

Pass `--full-scan` / `-FullScan` only if the user explicitly asks to reprocess
all lessons history.

Output lines: `INPUT=<path>`, `FILES=<n>`, `LATEST_EPOCH=<int>`, `CURSOR=<path>`,
`MASTER=<path>`.

## Step 2 — Check for work

If `FILES=0`, report "No new lessons to harvest" and stop. Do not commit or touch
the cursor.

## Step 3 — Read inputs

Read the `INPUT` file (one `## Source: <path>` section per session, each followed
by `Date:` and the session's lessons). Note the run date from the
`# Lessons Harvest Input — YYYY-MM-DD` header; call it `RunDate`.

Read the `MASTER` file if it exists, noting every existing `### ` lesson title for
deduplication. If it does not exist, treat it as empty.

## Step 4 — Analyse and filter

For each lesson across all source sections:

- **Keep** if it is project-generic: applies to multiple codebases, describes a
  mistake / better approach / useful discovery about a tool, pattern, or workflow
  any developer could hit, and does not depend on one repo's tech choices or
  team-specific conventions.
- **Discard** if it is purely one project's domain/naming/config, already in the
  master (by title or near-identical content), or too vague to act on.

## Step 5 — Update the master file

If no new lessons passed the filter, skip this step — leave the master file
untouched.

Otherwise: if the master file does not exist, create it with:

```markdown
# Master Lessons Learned

Cross-project lessons harvested weekly from daily session notes.
Last updated: <RunDate>
```

Append each new generic lesson under the right `## Category` heading (create it if
missing). Categories: `Architecture`, `Debugging`, `Performance`, `Security`,
`Testing`, `Tooling`, `Workflow`, `API behaviour`, `Database`, `Other`.

Lesson format:

```markdown
### <short descriptive title>
**Source**: <source filename> (<RunDate>)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
```

Update the `Last updated:` line to `RunDate`.

## Step 6 — Advance the cursor

Write the `LATEST_EPOCH` value (the integer from Step 1, nothing else) to the
`CURSOR` file. Do this whether or not any lesson passed the filter — it marks
these source files as harvested so they are not reprocessed next run. Only skip it
if an error stopped you from completing the analysis.

## Step 7 — Commit

Run git-sync from the meta repo:

- Windows: `& "$env:CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "weekly-lessons"`
- macOS / Linux: `bash "$CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "weekly-lessons"`

git-sync writes its own run log under `logs/` *after* it commits, so that log is left
uncommitted. Make one trailing commit to capture it (a plain commit creates no new log,
so it terminates): in `$CLAUDE_META_DIR` run `git add -A`, and if anything is staged,
`git commit -m "weekly-lessons: git-sync log"` then `git push` if a remote is configured.

## Step 8 — Report

Print: `Harvest complete for <RunDate>. Checked M sessions, added N new lessons to
the master file.` State explicitly if no new generic lessons were found.
