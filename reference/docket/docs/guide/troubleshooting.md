# Troubleshooting

Common stumbles while *using* docket. For installing, configuring, or recovering the system, see
the [Operations runbook](operations/runbook.md).

## "No projects — edit .docket.json"

docket didn't find a registry, or it's empty. docket searches, first match wins: `--registry PATH`
→ `$DOCKET_REGISTRY` → `./.docket.json` → `~/.config/docket/.docket.json`. Generate one with
`docket init` (or fix the existing file) — see
[Configure the registry](operations/configure-registry.md).

## My project shows but has no plans

docket lists files matching `<repo>/.agents_workspace/planning/**/*.md`. If there are none, nothing
shows. Confirm the plan files exist at that path. Nested folders are fine — a plan at
`planning/feature-x/ITER_01.md` gets the slug `feature-x/ITER_01`.

## The Implement button is disabled / pressing `i` does nothing

Headless **Implement** is available only when the plan is `ready` or `implemented`. A `running`
plan can't be implemented again. If a plan is wrongly stuck at `running`, see [a plan is stuck in
running](operations/runbook.md#incident-a-plan-is-stuck-in-running).

## "Mark implemented" or "Reopen" is rejected

These are manual transitions with strict rules:

- **Mark implemented** works only from `ready`.
- **Reopen** works only from `implemented`.
- Neither works on a `running` plan.

See the legal transitions in the [Reference](reference.md#lifecycle).

## A run is stuck, or I want to cancel it

Trigger **Stop** (TUI: press **s**; browser: click **Stop**). docket terminates the headless
process; the plan reverts to `ready`. In a batch, stopping a run also skips that project's
remaining plans (other projects continue). If docket itself died mid-run and a plan is still shown
as `running`, restart docket — startup recovery resets it. See the
[runbook](operations/runbook.md#incident-a-plan-is-stuck-in-running).

## The clipboard didn't get the plan body (Run myself)

docket falls back gracefully and prints the command to the log; copy it from there. The browser
clipboard API requires a secure context — `127.0.0.1` qualifies, but some browsers still block it.
The command shown in the log is all you need.

## The log stopped streaming / "stream interrupted"

The browser uses Server-Sent Events. On a dropped connection it auto-reconnects and resumes
draining the live queue, but lines delivered before the drop are not replayed (the queue is
drained once — acceptable for a local tool). If you see "stream interrupted — refresh to see final
status", refresh the page; the plan's badge reflects the true final status from its sidecar.

## My edits weren't committed

By design. A headless run leaves working-tree changes and docket never commits. Review and commit
yourself:

```bash
cd <repo> && git diff
```
