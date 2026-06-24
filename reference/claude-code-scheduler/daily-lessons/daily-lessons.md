# Extract Lessons Learned from Chat Session

Read a pre-extracted chat transcript and extract lessons learned using the
ceh-lessons-learned skill. The trigger script handles moving the output file
to its final named location after this prompt completes.

---

## Step 1 — Read the input file

Read `$CLAUDE_META_DIR/.claude/scripts/lessons-input.md`.

Parse the header fields:
- `UUID` — session identifier
- `Date` — date of the chat (YYYY-MM-DD)
- `Title` — session title
- `Project` — project directory name

The `## Conversation` section contains the extracted transcript with `[USER]` and
`[ASSISTANT]` turn markers. Treat this as the conversation to analyse.

---

## Step 2 — Extract lessons learned

Invoke the `/ceh-lessons-learned:lessons-learned` skill on the conversation
transcript you just read.

The skill will write lessons to `docs/claude_logs/LESSONS_LEARNED.md` relative
to the working directory. Do not change the output path — the trigger script
will rename and move the file after this prompt completes.

If the transcript contains no meaningful lessons (e.g. trivial session, no
decisions or mistakes), still invoke the skill so it can make that judgement.

---

## Step 3 — Report

Print a single line:
> "Lessons extracted for <UUID> (<Date>)."
