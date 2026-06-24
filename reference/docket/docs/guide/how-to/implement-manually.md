# Implement a plan manually

Run Claude Code yourself in your own terminal, and use docket only to hand you the command and
record the outcome. No subprocess, no `running` state.

**When:** you want to drive the session yourself (interactive, custom flags, your own review loop)
but still track the plan's lifecycle in docket.
**Prerequisites:** the plan's project is in your registry. The `claude` CLI is needed only in
*your* terminal, not by docket.
**Time / impact:** none on docket's side until you mark the result.

## Steps

1. Select the plan (TUI: arrow + **Enter**; browser: click the row).
2. Trigger **Run myself** (TUI: press **r**; browser: click **Run myself**).
   - docket copies the **plan body** to your clipboard.
   - docket prints a copy-pasteable command to the log, of the form:

     ```bash
     cd <project.path> && claude -p < .agents_workspace/planning/<slug>.md
     # or: cd <project.path> && claude   (then paste / @-mention the plan file)
     ```

   **Verify:** the command appears in the log and the plan's status is **unchanged** (still
   `ready`) — docket isn't running anything; you are.
3. Paste the command into your own terminal and run the session to completion.
4. Back in docket, trigger **Mark implemented** (TUI: press **m**; browser: click **Mark
   implemented**).

**Verify:** the badge flips `ready → implemented`, and the transition is logged in the sidecar
with `trigger: "manual"`.

## If it fails

- **Clipboard unavailable.** docket logs "clipboard unavailable" (TUI) or "clipboard unavailable —
  copy the command shown in the log" (browser). Copy the printed command manually; the browser
  clipboard API needs a secure context, which `127.0.0.1` provides.
- **Mark implemented is rejected.** Manual marking is allowed only from `ready`. If the plan is
  `running` or `implemented`, the action is refused with a notice. To re-mark an already-finished
  plan, [reopen it first](re-run-and-reopen.md).
