# Session extraction

The cleaned transcript of one Claude Code session follows on standard input. It starts with a
short header (`UUID`, `Date`, `Title`, `Project`, `Cleanup`) and then a `## Conversation`
section, where each block starts with a label:

- `[USER]`: text the user typed.
- `[ASSISTANT]`: the assistant's reply.
- `[QUESTION]`: a multiple-choice question the assistant asked, with its options.
- `[ANSWER]`: the user's answer to that question, with any notes they added.
- `[USER REJECTED <tool>]`: the user refused that tool call. Their reason, if they gave one, is
  their next `[USER]` block.
- `[INTERRUPTED]`: the user stopped the assistant mid-reply.

Tool calls and tool output are not part of the transcript.

Do not use any tools. Answer with the parts listed below only, in this order. Start each part
with its marker line, exactly as shown, on a line of its own, followed by that part's file
content. Write nothing before the first marker and nothing after the last part.

{{PARTS}}

The instructions for each part follow.
