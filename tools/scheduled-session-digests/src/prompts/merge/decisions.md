# Weekly decisions merge

Fold this week's decision records into SOUL.md: the short file every Claude Code session of
this user loads, so agents decide the way the user would. Your input follows on standard input.
It starts with a `Run date: YYYY-MM-DD` line, then has three sections:

- `# Current file`: SOUL.md as it is now (or `(none yet)`).
- `# Open questions`: the `### ` titles of questions already asked and not yet answered (or
  `(none)`).
- `# New session files`: one `## Source: <file name>` section per file. A per-session file
  holds that session's decisions, each with Situation, Options, Chosen, Reason, Reason source
  (`stated`, `inferred`, or `none` when the user gave no reason), Override, and Domain. A file named `issue-<n>.md` is the user's
  answer to an earlier question: its Reason is the user's own words, and a bare number there
  picks that numbered option from its Situation.

Do not use any tools.

## How to merge

- Write rules shaped "When X, prefer Y, because Z, unless W." Every rule has a "because" and,
  when the records show one, an "unless".
- Only the user's words are reasons. A `stated` reason outranks an `inferred` one, and an
  override (the user correcting the assistant's default) weighs more than a choice the user
  did not object to.
- Keep what the current file says unless new records change it. A record that contradicts an
  existing rule refines its "unless" when the records show what differs between the cases;
  when they do not, keep the rule and ask a question.
- A rule resting only on `inferred` or `none` reasons becomes a question, not a rule.
- When several rules point the same way, state the shared priority under `## Priorities`, in
  order of weight.
- Never ask a question listed under `# Open questions` again. When it still applies, reuse its
  exact title.
- Stay within {{MAX_LINES}} lines by merging and retiring rules, never by cutting text short.
- Leave out tool and execution tips (which command to run, how to read a file).

## Answer

Answer with two parts, each starting with its marker line, exactly as shown, on a line of its
own. Write nothing before the first marker and nothing after the last part.

<<<extraction:soul>>>
The whole new SOUL.md, in this shape:

```markdown
# SOUL

## Priorities

1. <priority>, because <reason>.

## Rules

### <domain>

- When <situation>, prefer <choice>, because <reason>, unless <exception>.
```

Do not write a `## When to ask` section: the script adds it.

<<<extraction:questions>>>
Each new question for the user, as below. Everything under the `### ` line becomes the body of
a GitHub issue, so write it as Markdown that reads at a glance, and never start a body line
with `### `. Number the options from 1, the recommended one first and marked "(recommended)",
so the user can answer with a number.

```markdown
### <the question, one line, ending with "?">

**Situation**

<what happened and why it needs the user's call, in two or three sentences>

**Options**

1. <option> (recommended): <why>
2. <option>: <trade-off>

**Answer** with the option's number, plus a reason if you have one.

<sub>Sources: <the source file names, comma-separated></sub>
```

or, when there is nothing to ask, exactly:

```
_No questions._
```
