# Re-run or reopen a plan

A plan that reached `implemented` isn't frozen. You can run it again headless, or send it back to
`ready` to re-mark or hand-run it.

## Re-run an implemented plan (headless)

A re-run is a brand-new `claude -p` session with fresh instruction text — nothing is appended to
any prior run.

**When:** the plan is `implemented` and you want follow-up work, or to run it again with a
different instruction.
**Prerequisites:** the `claude` CLI installed and authenticated.

1. Select the implemented plan.
2. Start a headless run exactly as for a first run — TUI: press **i**; browser: click
   **Implement**. (The control is enabled for both `ready` and `implemented` plans.)
3. The instruction box opens pre-filled; edit it to describe the follow-up, then confirm.

**Verify:** the badge goes `implemented → running`, then back to `implemented` on success (or
`ready` on failure). A new transition is appended to the plan's history.

Full streaming and failure details: [Implement a plan headless](implement-headless.md).

## Reopen an implemented plan (back to ready)

**When:** you want to re-mark the plan manually, hand-run it again, or simply clear its
`implemented` status.

1. Select the implemented plan.
2. Trigger **Reopen** (TUI: press **o**; browser: click **Reopen**, shown only when the plan is
   `implemented`).

**Verify:** the badge flips `implemented → ready`, logged with `trigger: "manual"`.

## Rules to know

- **Reopen only works from `implemented`.** From any other status it's refused with a notice.
- **A `running` plan cannot be re-run, marked, or reopened** — it's already in flight. Wait for it
  to finish or stop it first.
- Manual transitions never produce `running`; only headless runs do.

The full set of legal transitions is in the [Reference](../reference.md#lifecycle).
