# docket Guide

docket is a single local command-center over the Claude Code repos you work across. It reads a
JSON registry of your repos, shows every plan and its lifecycle status in one place, and lets you
implement plans — by hand or headless via `claude -p` — from a terminal UI or a localhost browser
page, without `cd`-ing between repos.

This guide has two halves. Use the one that matches what you are doing right now:

- **User guide** — you want to *run plans*: pick a plan, implement it, mark it done, re-run it.
- **Operator guide** — you want to *stand docket up and keep it healthy*: install it, write the
  registry, recover a run that got stuck.

For a single-user local tool the same person usually does both, but the tasks are kept separate so
you can jump straight to the one you need.

## User guide

| Page | Read it when |
|------|--------------|
| [Runnable example](../../examples/README.md) | You want to see docket working immediately, with no setup. |
| [Getting started](getting-started.md) | First time — go from nothing to one implemented plan. |
| [Implement a plan headless](how-to/implement-headless.md) | You want docket to run `claude -p` for you and stream the output. |
| [Implement a plan manually](how-to/implement-manually.md) | You want to run Claude Code yourself and just track the outcome. |
| [Implement a batch of plans](how-to/batch-implement.md) | You want to submit many plans at once. |
| [Re-run or reopen a plan](how-to/re-run-and-reopen.md) | A plan is `implemented` and you want to run it again or send it back to `ready`. |
| [Troubleshooting](troubleshooting.md) | Something in the UI isn't behaving. |

## Operator guide

| Page | Read it when |
|------|--------------|
| [Install docket](operations/install.md) | Setting docket up on a machine. |
| [Configure the registry](operations/configure-registry.md) | Telling docket which repos exist and how to run them. |
| [Operations runbook](operations/runbook.md) | Starting/stopping the server, and recovering from incidents (stuck `running`, port in use, empty registry). |

## Reference

- [Reference](reference.md) — CLI commands and flags, TUI key bindings, browser controls, the
  lifecycle state machine, and every registry field.

## Key facts

- **Plans are read-only to docket.** It never creates, edits, or deletes a file under
  `.agents_workspace/planning/`. You author plans with the planning skill.
- **Status lives in a sidecar**, not the plan. docket owns one JSON file per plan under
  `.agents_workspace/implementation/<slug>.json`. Delete that tree and you lose status/history
  only — never a plan. A plan with no sidecar is `ready`.
- **docket never handles API keys.** Headless runs shell out to the `claude` CLI, which you
  install and authenticate yourself.
- **docket never commits.** A run leaves working-tree changes; reviewing the diff is your final
  step.
