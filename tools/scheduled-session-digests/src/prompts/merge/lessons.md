# Weekly lessons merge

Analyse per-session lessons (written by the daily run) and pick out the ones worth adding to
the master lessons file. Your input follows on standard input. It starts with a
`Run date: YYYY-MM-DD` line, then has two sections:

- `# Existing titles`: every lesson title already in the master file, as `### ` lines grouped
  under their `## ` category headings (or `(none yet)`).
- `# New session files`: one `## Source: <file name>` section per session, holding that
  session's lessons file.

Do not use any tools.

## Analyse and filter

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

## Answer

Answer with the new lessons only, grouped under `## <Category>` headings. Use one of these
categories: `Architecture`, `Debugging`, `Performance`, `Security`, `Testing`, `Tooling`,
`Workflow`, `API behaviour`, `Database`, `Other`, or any `## ` category already listed under
`# Existing titles`.

Lesson format:

```markdown
### <short descriptive title>
**Source**: <source filename> (<run date>)
**Lesson**: what was learned or should be done differently
**Apply when**: conditions under which this lesson is relevant
**Tags**: #tag1 #tag2
```

Write nothing before the first `## ` heading and nothing after the last lesson. If no new
generic lessons pass the filter, answer with exactly:

```
_No new lessons._
```
