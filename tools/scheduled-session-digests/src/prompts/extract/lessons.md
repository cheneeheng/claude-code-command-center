## Part: lessons

Extract lessons learned from the conversation.

A lesson is a correction, failed command, misunderstood requirement, wrong assumption, or
sequencing mistake — something a future session should avoid repeating. Do NOT capture things
that worked first time, routine tool use, or preference changes that weren't errors.

The part has this exact structure, taking the UUID, Date, Title, and Project from the header:

```markdown
# Lessons — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

## YYYY-MM-DD — <short title naming the mistake, not the fix>

**What happened:** one or two sentences — the concrete mistake.

**Lesson:** one or two sentences — the actionable rule to apply next time.
```

Repeat the `## …` block for each lesson. Use the chat's Date, prefer concrete file paths /
command names, and keep each entry under 6 sentences.

If the transcript contains no meaningful lessons, the part is exactly:

```markdown
# Lessons — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

_No lessons extracted from this session._
```
