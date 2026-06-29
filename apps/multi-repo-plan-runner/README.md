# docket

A single local command-center over the ~10 Claude Code repos you work across. docket reads a
JSON registry of your repos, surfaces every plan and its lifecycle status in one view, and lets
you implement plans — singly or as a per-project sequential batch — without leaving the tool.

Plans are markdown files **you author with the planning skill**, living under each repo's
`.agents_workspace/planning/`. **docket never creates, edits, or deletes a plan** — it only
reads them. The mutable state docket owns lives separately under
`.agents_workspace/implementation/`: one JSON sidecar per plan holding that plan's lifecycle
status and full transition history. Delete `implementation/` and you only lose status/history,
never a plan.

A plan moves through `ready → running → implemented`, driven two ways — **headless** (docket runs
`claude -p` in the repo and streams the output) or **manual** (you run Claude Code yourself and
mark the result). Submit many plans at once and docket groups them by project, running each
project's plans sequentially and different projects concurrently. Two interchangeable frontends sit
over one shared core: a Textual **TUI** and a localhost **browser page** (`127.0.0.1` only).

Python 3.11+. The only pip dependency is `textual` (the browser side is pure stdlib). The `claude`
CLI is BYO — docket shells out to it for headless runs and never handles API keys.

## Quick start

See it working immediately, no setup — from this directory (`apps/multi-repo-plan-runner/`):

```bash
uv run docket --registry examples/docket.json tui
```

That loads the [runnable example](examples/README.md): two sample repos with plans and a ready-made
registry. When you're ready for your own repos, follow [Getting started](docs/guide/getting-started.md).

## Documentation

Full guide under [`docs/guide/`](docs/guide/index.md):

| Page | For |
|------|-----|
| [Getting started](docs/guide/getting-started.md) | Nothing to one implemented plan. |
| [Runnable example](examples/README.md) | A populated UI with zero setup. |
| [How-to guides](docs/guide/index.md#user-guide) | Headless, manual, batch, re-run/reopen. |
| [Install](docs/guide/operations/install.md) · [Configure the registry](docs/guide/operations/configure-registry.md) · [Runbook](docs/guide/operations/runbook.md) | Standing docket up and keeping it healthy. |
| [Reference](docs/guide/reference.md) | CLI, key bindings, lifecycle state machine, every registry field. |
| [Troubleshooting](docs/guide/troubleshooting.md) | Something in the UI isn't behaving. |

## Limitations (MVP)

- The per-project lock serializes same-repo headless runs **within one process** — running the TUI
  and the server against the **same repo simultaneously** is not cross-process-locked.
- The TUI streams one run at a time; the browser streams concurrent per-project batches.
- docket leaves working-tree changes; it does **not** commit. Reviewing the diff is your final step.
