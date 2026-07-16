# Extract Lessons Learned from Chat Session

Read a pre-extracted chat transcript, extract lessons learned, and write them
directly to the output file. The trigger script substitutes the file paths below
before passing this prompt to `claude --print`.

- Input file : `{{INPUT_FILE}}`
- Output file: `{{OUTPUT_FILE}}`

---

## Step 1 — Read the input file

Read the input file. It has a header (`UUID`, `Date`, `Title`, `Project`, `CWD`,
`Output`) followed by a `## Conversation` section containing the transcript with
`[USER]` and `[ASSISTANT]` turn markers.

---

## Step 2 — Extract lessons learned

A lesson is a correction, failed command, misunderstood requirement, wrong
assumption, or sequencing mistake — something a future session should avoid
repeating. Do NOT capture things that worked first time, routine tool use, or
preference changes that weren't errors.

---

## Step 3 — Write the output file

Create the parent directory of the output file if needed, then write the output
file with this exact structure:

```markdown
# Lessons — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

## YYYY-MM-DD — <short title naming the mistake, not the fix>

**What happened:** one or two sentences — the concrete mistake.

**Lesson:** one or two sentences — the actionable rule to apply next time.
```

Repeat the `## …` block for each lesson. Use the chat's Date, prefer concrete
file paths / command names, and keep each entry under 6 sentences.

If the transcript contains no meaningful lessons, instead write the output file
with exactly:

```markdown
# Lessons — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

_No lessons extracted from this session._
```

The output file must always be created (real lessons or the stub) — its
existence marks the session as processed.

---

## Step 4 — Report

Print a single line: the output path and how many lessons you wrote.
