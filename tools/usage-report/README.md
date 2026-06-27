# usage-report

A CLI that prints a cross-session summary of Claude Code **token usage and estimated cost** —
the terminal counterpart to the [`usage-dashboard`](../../apps/usage-dashboard/) app. Both read
the same data through the [`claude-usage`](../../libs/claude-usage/) library.

```console
$ uv run usage-report --top 5
42 sessions  |  18.7M tokens  |  $124.53 estimated

Top 5 sessions by cost:
  3f9a1c2b my-project          2.1M  $   18.40
  ...

Top 5 projects by cost:
  my-project                   9.3M  $   61.20
  ...

By model:
  claude-opus-4-8             12.1M  $   98.10
  claude-sonnet-4-6            6.6M  $   26.43
```

Cost is **estimated** (token counts × list price), not the amount Anthropic billed.
Honours `$CLAUDE_DIR`. Run with `uv run usage-report` (or install the package and run
`usage-report`).
