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
Honours `$C4_CLAUDE_DIR`. Run with `uv run usage-report` (or install the package and run
`usage-report`).

## Setup

Unlike the stdlib-only `tools/` scripts, this is a real installable package: it has a
`[build-system]`, a `usage-report` console entry point, and a runtime dependency on the local
[`claude-usage`](../../libs/claude-usage/) library (wired as an editable path source). So you
must sync the environment before first use:

```bash
uv sync                  # creates .venv with claude-usage + dev tools
uv run usage-report --top 5
```

`uv sync` also installs the `dev` group (`ruff`, `mypy`) for linting and type-checking:

```bash
uv run ruff check .
uv run mypy src
```
