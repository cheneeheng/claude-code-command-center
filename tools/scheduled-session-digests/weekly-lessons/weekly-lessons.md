# Weekly Lessons Harvest

Analyse pre-collected per-session lessons from daily-lessons output and update the master
lessons file. The trigger script has already scanned the lessons-learned directory,
filtered out stubs, and written the content to an input file. Your job is analysis,
deduplication, and writing.

---

## Step 1 — Read the collected lessons

Read `$CLAUDE_META_DIR/.claude/scripts/weekly-lessons-input.md`.

This file contains one section per session, each starting with `## Source: <path>`,
followed by a `Date:` field and the full content of that session's lessons file (written
by daily-lessons from the ceh-lessons-learned skill).

Note the run date from the `# Lessons Harvest Input — YYYY-MM-DD` header.
Set `$RunDate` to that date.

---

## Step 2 — Read the existing master lessons file

Set `$MasterFile` = `$CLAUDE_META_DIR/master-lessons/MASTER_LESSONS_LEARNED.md`.

If it exists, read it in full. Note all lesson titles already present (`### ` headings)
to use for deduplication in Step 3.

If it does not exist, treat as empty and create it with the header in Step 4.

---

## Step 3 — Analyse and filter

For each lesson across all source sections, decide:

**Keep (project-generic)** if the lesson:
- Applies to multiple projects or codebases without modification
- Describes a mistake, better approach, or useful discovery about a tool, pattern,
  or workflow that any developer could encounter
- Does not reference repo-specific technology choices, internal services, or
  team-specific conventions that don't generalise

**Discard** if the lesson:
- Is purely about one project's domain model, naming, or config
- Is already present in the master file (by title or near-identical content)
- Is too vague to be actionable ("write better tests")

For lessons you keep, note the source filename and date.

---

## Step 4 — Update the master lessons file

If no new lessons passed the filter, skip this step entirely — do not modify the file.

Otherwise:

If the file does not exist, create it:
```markdown
# Master Lessons Learned

Cross-project lessons harvested weekly from daily session notes.
Last updated: YYYY-MM-DD
```

For each new generic lesson, append under the appropriate `## Category` heading
(create the heading if it does not exist). Categories:
`Architecture`, `Debugging`, `Performance`, `Security`, `Testing`, `Tooling`,
`Workflow`, `API behaviour`, `Database`, `Other`.

Lesson format:
```markdown
### [Short descriptive title]
**Source**: <filename> ($RunDate)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
```

Update the `Last updated:` line at the top to $RunDate.

---

## Step 5 — Report

Print a summary:
> "Harvest complete for $RunDate. Checked M sessions, added N new lessons to master file."

If no new generic lessons were found, say so explicitly.
