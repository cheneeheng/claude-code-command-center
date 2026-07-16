# Weekly Lessons Harvest

Analyse pre-collected per-session lessons (written by daily-lessons) and update
the master lessons file. The prepare script has already scanned the
lessons-learned directory, filtered out stubs, and collected the content into
the input file. Your job is analysis, deduplication, and writing. The trigger
script substitutes the file paths below before passing this prompt to
`claude --print`.

- Input file : `{{INPUT_FILE}}`
- Master file: `{{MASTER_FILE}}`

---

## Step 1 — Read the collected lessons

Read the input file. It contains one section per session, each starting with
`## Source: <path>`, followed by a `Date:` field and the full content of that
session's lessons file.

Note the run date from the `# Lessons Harvest Input — YYYY-MM-DD` header.
Call it `RunDate`.

---

## Step 2 — Read the existing master lessons file

If the master file exists, read it in full and note all lesson titles already
present (`### ` headings) for deduplication in Step 3.

If it does not exist, treat it as empty and create it in Step 4.

---

## Step 3 — Analyse and filter

For each lesson across all source sections, decide:

**Keep (project-generic)** if the lesson:

- Applies to multiple projects or codebases without modification
- Describes a mistake, better approach, or useful discovery about a tool,
  pattern, or workflow that any developer could encounter
- Does not reference repo-specific technology choices, internal services, or
  team-specific conventions that don't generalise

**Discard** if the lesson:

- Is purely about one project's domain model, naming, or config
- Is already present in the master file (by title or near-identical content)
- Is too vague to be actionable ("write better tests")

For lessons you keep, note the source filename.

---

## Step 4 — Update the master lessons file

If no new lessons passed the filter, skip this step entirely — do not modify
the file.

Otherwise, if the master file does not exist, create it (including parent
directories) with:

```markdown
# Master Lessons Learned

Cross-project lessons harvested weekly from daily session notes.
Last updated: <RunDate>
```

Append each new generic lesson under the appropriate `## Category` heading
(create the heading if it does not exist). Categories: `Architecture`,
`Debugging`, `Performance`, `Security`, `Testing`, `Tooling`, `Workflow`,
`API behaviour`, `Database`, `Other`.

Lesson format:

```markdown
### <short descriptive title>
**Source**: <source filename> (<RunDate>)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
```

Update the `Last updated:` line at the top to `RunDate`.

---

## Step 5 — Report

Print a summary:
> "Harvest complete for <RunDate>. Checked M sessions, added N new lessons to the master file."

If no new generic lessons were found, say so explicitly.
