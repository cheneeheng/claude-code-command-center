---
name: session-digest-weekly-lessons
description: Run the weekly-lessons harvest from inside an interactive Claude Code session instead of via the cron/Task Scheduler trigger (which calls `claude --print` and burns programmatic credit). Use when the user asks to "run weekly lessons", "harvest lessons", or "update the master lessons file". The prepare script collects the week's per-session lessons; you distil the project-generic ones into the master file directly, advance the cursor, then git-sync. No subagents are needed — this is a single analysis job.
---

# Weekly Lessons — interactive harvest

The prepare script collects every per-session lessons file written since the last
harvest into one input file. You read it, distil the project-generic lessons into
the master file, advance the cursor, commit, and clean up. No `claude --print`
is used.

This is a single inline analysis job — there is no subagent to pin a model on, so it
runs on whatever model and effort this coordinator session uses. The cron trigger runs
this harvest on `opus` at `--effort high` because the dedup/generalisation judgement is
the hardest step and pollutes the permanent master file if done poorly; for parity, run
this session on Opus at high effort.

## Step 1 — Run the prepare script

`C4_CLAUDE_META_DIR` must be set (the scheduler's `~/.claude/claude-scheduler.env`
sets it; the prepare script also sources that file). Scripts are installed at
`$C4_CLAUDE_META_DIR/.claude/scripts/`.

Run the script for the current OS and capture stdout:

- Windows (PowerShell tool):
  `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\weekly-lessons-prepare.ps1"`
- macOS / Linux (Bash tool):
  `bash "$C4_CLAUDE_META_DIR/.claude/scripts/weekly-lessons-prepare.sh"`

Pass `--full-scan` / `-FullScan` only if the user explicitly asks to reprocess
all lessons history.

The last lines of output are `MANIFEST=<path>` and `JOBS=<n>` (the number of
collected source files).

## Step 2 — Read the manifest

Read the `MANIFEST` file. It is a JSON object:

```json
{ "scheduler": "weekly-lessons",
  "cursor": "<cursor file path>",
  "cursorEpoch": <epoch to write to the cursor after a successful harvest>,
  "files": <number of collected source files>,
  "input": "<harvest input file path>",
  "master": "<master lessons file path>" }
```

If `files` is 0, delete the staging directory (the manifest's parent directory),
report "No new lessons to harvest", and stop. Do not commit or touch the cursor.

## Step 3 — Read inputs

Read the `input` file (one `## Source: <path>` section per session, each followed
by `Date:` and the session's lessons). Note the run date from the
`# Lessons Harvest Input — YYYY-MM-DD` header; call it `RunDate`.

Read the `master` file if it exists, noting every existing `### ` lesson title for
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

Otherwise: if the master file does not exist, create it (including parent
directories) with:

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

Write the `cursorEpoch` value (the integer from the manifest, nothing else) to the
`cursor` file. Do this whether or not any lesson passed the filter — it marks
these source files as harvested so they are not reprocessed next run. Only skip it
if an error stopped you from completing the analysis.

## Step 7 — Commit

Run git-sync from the meta repo:

- Windows: `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "weekly-lessons"`
- macOS / Linux: `bash "$C4_CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "weekly-lessons"`

git-sync is self-contained: run logs under `logs/` are gitignored (local-only), and if
the session is on a feature branch (e.g. one forced by a branch guard) git-sync merges
it into the default branch and deletes it, so the digest lands on main. Do not make any
extra commits.

## Step 8 — Clean up and report

Delete the staging directory
(`$C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/weekly-lessons/`) — the
harvest input and manifest are no longer needed.

Print: `Harvest complete for <RunDate>. Checked M sessions, added N new lessons to
the master file.` State explicitly if no new generic lessons were found.
