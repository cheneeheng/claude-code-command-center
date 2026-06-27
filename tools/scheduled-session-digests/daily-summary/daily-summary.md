# Summarise Chat History

Read a pre-extracted chat transcript and write a concise summary to the output path
specified in the input file header.

---

## Step 1 — Read the input file

Read `$C4_CLAUDE_META_DIR/.claude/scripts/chat-input.md`.

Parse the header fields:
- `UUID` — session identifier
- `Date` — date of the chat (YYYY-MM-DD)
- `Title` — session title
- `Project` — project directory name
- `Output` — full path to write the summary to

The `## Conversation` section contains the extracted transcript with `[USER]` and
`[ASSISTANT]` turn markers.

---

## Step 2 — Write the summary

Write the summary to the path specified in `Output`.

```markdown
# Chat Summary — YYYY-MM-DD
**Session**: UUID
**Title**: Title
**Project**: Project

## What was worked on
<Bullet list of the main tasks, features, or investigations in this session.
 Derive from what the user asked and what was built or changed.>

## Decisions made
<Architectural, design, or tooling decisions and their rationale.
 Skip this section if none were made.>

## Outcomes
<What was actually completed, created, or fixed. Be specific — file names,
 function names, commands are useful here.>

## Current State
<Files created, modified, or deleted this session. Use sub-bullets:
 - Created: `path/to/file` — purpose
 - Modified: `path/to/file` — what changed
 - Deleted: `path/to/file`
 Skip this section if no files changed.>

## Pending / Next Steps
<Work discussed but not completed, or logical next actions. Use checkboxes.
 Skip this section if none.>

## Key Facts for Next Session
<Non-obvious facts a future LLM must know to avoid repeating mistakes or
 asking redundant questions. Skip this section if none.>

## Open items
<Unresolved questions or explicit next steps mentioned in the conversation.
 Skip this section if none.>
```

Rules:
- Keep the whole file under 80 lines.
- Be concrete. Avoid generic statements like "discussed the codebase."
- If the conversation is very short or contains no meaningful work, write a
  one-line `## Note` instead: `No significant work recorded.`
