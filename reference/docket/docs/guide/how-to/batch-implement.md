# Implement a batch of plans

Submit several plans in one action. docket groups them **by project** and runs each project's
plans **sequentially**; different projects run **concurrently**. If one plan in a project fails or
is stopped, that project's remaining plans are skipped — other projects keep going.

**When:** you have multiple `ready`/`implemented` plans to run and don't want to start them one by
one.
**Prerequisites:** same as a [headless run](implement-headless.md) — the `claude` CLI installed and
authenticated, and every selected plan in a registered project.
**Time / impact:** runs edit working trees across the selected repos. No commits.

## Steps (TUI)

1. For each plan you want to include, select it and press **Space** to toggle it into the batch. A
   `✓` appears next to selected plans.
2. Press **Shift+I** (the `I` binding, "Implement selected").

**Verify:** the log shows a `── <project>/<slug> ──` header for each plan as it starts. The MVP TUI
streams **one run at a time**, processing the selection project-by-project, plan-by-plan.

## Steps (browser)

1. Tick the checkbox on each plan row you want to include. The **Implement selected** button in
   the header enables once at least one box is ticked.
2. Click **Implement selected**.
3. For each selected plan a prompt appears, pre-filled with that plan's resolved instruction. Edit
   each one if you want a different instruction per plan, and confirm. Cancelling any prompt
   cancels the whole batch.

**Verify:** each run streams into its own labelled log section. Different projects' runs stream
**concurrently**; plans within one project stream in order. A plan skipped by stop-on-failure shows
its end event immediately as `— skipped —`.

## Stop-on-failure behaviour

- A plan that ends `failed` or is `stopped` causes every *remaining* plan **in the same project**
  to be marked `skipped`.
- Plans in *other* projects are unaffected and continue.

## If it fails

- **The whole submission is rejected before anything starts.** If any item names an unknown
  project, an invalid slug, or a non-runnable plan (already `running`), docket rejects the entire
  batch and starts nothing. Fix the offending item and resubmit.
- **A project stops early.** That's stop-on-failure. Read that project's first failing log to find
  the cause; re-run just those plans once fixed.
