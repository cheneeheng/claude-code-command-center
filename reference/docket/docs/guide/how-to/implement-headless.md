# Implement a plan headless

Let docket run `claude -p` inside the repo and stream the output live, flipping the plan to
`running` and then `implemented` on success.

**When:** the plan is `ready` or `implemented` and you want docket to do the run unattended.
**Prerequisites:**

- The `claude` CLI is installed and authenticated (`claude --version` works).
- The plan's project is in your registry.

**Time / impact:** as long as the agent takes. The run edits files in the repo's working tree.
docket does **not** commit — you review the diff afterward.

> **Warning:** a headless run applies edits automatically (`--permission-mode acceptEdits`), scoped
> to the project's `allowed_tools` allowlist. Anything outside the allowlist is denied, never
> prompted. Point docket only at repos whose working tree you are willing to let the agent change.

## Steps (TUI)

1. Select the plan (arrow to it, press **Enter**). The body renders on the right.
2. Press **i**. An instruction box opens, pre-filled with the resolved instruction template — a
   short instruction that *names the plan file*. The plan body itself is never piped; Claude Code
   opens the file.
3. Edit the instruction if you want, then press **Enter** to start (or **Esc** to cancel).

**Verify:** the badge flips to **running** (`▶`), and lines stream into the log pane at the
bottom. On completion the badge becomes **implemented** (`●`) and the log shows
`[docket] run completed`.

## Steps (browser)

1. Click the plan's row. Its controls appear.
2. Click **Implement**. A prompt opens, pre-filled with the resolved instruction.
3. Accept or edit the instruction and confirm.

**Verify:** a labelled log section appears and streams output; when it ends with `— done —` the
plan's badge updates to **implemented** on refresh.

## Verify the result

The run changed files but did not commit them. Review the diff yourself — this is the final step:

```bash
cd <repo> && git diff
```

If you're happy, commit as usual. If not, see [Re-run or reopen a
plan](re-run-and-reopen.md) to run it again, or discard the changes with your normal git workflow.

## If it fails

- **Badge returns to `ready` and the log shows `ended (rc=…)`.** The agent exited non-zero. Read
  the streamed log for the cause; fix the plan or environment and re-run.
- **"a run is already active for this project".** Another headless run is in flight for the same
  repo. docket serializes same-repo runs — wait for it to finish, or [stop
  it](../troubleshooting.md#a-run-is-stuck-or-i-want-to-cancel-it).
- **"…is 'running', not runnable".** The plan is already running. If no run is actually active,
  it's a stale status — see the [runbook](../operations/runbook.md#incident-a-plan-is-stuck-in-running).
- **`claude: command not found` in the log.** The CLI isn't installed or isn't on `PATH`. See
  [Install docket](../operations/install.md).
