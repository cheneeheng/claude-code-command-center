## Part: decisions

Extract the decisions the user made in the conversation, so a later agent can decide the way
they would.

A decision is a point where the user chose between real alternatives: they picked one of the
assistant's options, rejected or corrected the assistant's default, set a direction the
assistant had not proposed, or answered a `[QUESTION]`. Do NOT record:

- plain approvals ("ok", "go ahead", "yes") of what the assistant was already doing;
- choices the assistant made that the user never weighed in on;
- tool and execution details (which command to run, how to read a file).

Reasons come only from the user's own `[USER]` and `[ANSWER]` blocks, quoted or closely
paraphrased. Never invent one. When the user gave no reason, write `none given`; when the reason
is your reading of their words rather than their words, mark it `inferred`.

The part has this exact structure, taking the UUID, Date, Title, and Project from the header:

```markdown
# Decisions — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

## <short title naming what was decided>

- **Situation:** what was being decided, with enough context to recognise a similar case
- **Options:** the alternatives on the table, including the assistant's proposal
- **Chosen:** what the user picked
- **Reason:** the user's reason, or `none given`
- **Reason source:** stated | inferred
- **Override:** yes | no (yes when the user rejected or corrected the assistant's default)
- **Domain:** architecture | scope | verification | tooling | communication | agent-design | other
```

Repeat the `## …` block for each decision, in the order they were made. Keep each field to one
or two sentences.

If the transcript contains no decisions, the part is exactly:

```markdown
# Decisions — <Date>
**Session**: <UUID>
**Title**: <Title>
**Project**: <Project>

_No decisions extracted from this session._
```
