# Summarise Chat Session

Read a pre-extracted chat transcript and write a concise summary directly to the
output file. The trigger script substitutes the file paths below before passing
this prompt to `claude --print`.

- Input file : `{{INPUT_FILE}}`
- Output file: `{{OUTPUT_FILE}}`

---

## Step 1 — Read the input file

Read the input file. It has a header (`UUID`, `Date`, `Title`, `Project`, `CWD`,
`Output`) followed by a `## Conversation` section containing the transcript with
`[USER]` and `[ASSISTANT]` turn markers.

---

## Step 2 — Write the summary

Create the parent directory of the output file if needed, then write the summary
to the output file with this structure:

```markdown
# Chat Summary — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

## What was worked on
<Bullet list of the main tasks, features, or investigations in this session.
 Derive from what the user asked and what was built or changed.>

## Decisions made
<Architectural, design, or tooling decisions and their rationale.>

## Outcomes
<What was actually completed, created, or fixed. Be specific — file names,
 function names, commands are useful here.>

## Current State
<Files created, modified, or deleted this session. Use sub-bullets:
 - Created: `path/to/file` — purpose
 - Modified: `path/to/file` — what changed
 - Deleted: `path/to/file`>

## Pending / Next Steps
<Work discussed but not completed, or logical next actions. Use checkboxes.>

## Key Facts for Next Session
<Non-obvious facts a future LLM must know to avoid repeating mistakes or
 asking redundant questions.>

## Open items
<Unresolved questions or explicit next steps mentioned in the conversation.>
```

Rules:

- Skip any section that does not apply.
- Keep the whole file under 80 lines.
- Be concrete. Avoid generic statements like "discussed the codebase."
- If the conversation is very short or contains no meaningful work, write the
  header plus a single `## Note` section containing `No significant work
  recorded.` instead — the output file must always be created, because its
  existence marks the session as processed.

---

## Step 3 — Report

Print a single line: the output path you wrote.
