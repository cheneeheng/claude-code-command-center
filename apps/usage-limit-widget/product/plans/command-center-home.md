---
title: usage-limit-widget, run the widget from a copy under ~/.claude-command-center
status: built
created: 2026-11-05
---

## Goal

The logon task runs a copy of the widget at
`~/.claude-command-center/usage-limit-widget/claude_usage_widget.pyw` instead of the file in the
repo checkout, so moving or deleting the checkout does not break the widget, and the files the
command-center apps own sit next to its manifest. The user chose this over leaving the widget as is.

## Scope

**In:**

- `usage-limit-widget-setup.ps1` install: copy `claude_usage_widget.pyw` into
  `~/.claude-command-center/usage-limit-widget/` (no `-InstallDir`: nobody asked, and the registry
  records `@{}`, so a custom dir would be orphaned on uninstall), register the task with the copy as its argument and the
  install dir as its working directory. The interpreter stays the base one from
  `uv python find --system`, run from the app dir so the project's `requires-python` applies.
- Uninstall: stop and remove the task (as now), then delete the install dir.
- README: a `git pull` no longer reaches the running widget at the next hourly restart; re-run
  install to refresh the copy.
- README, CLAUDE.md, `product/ARCHITECTURE.md` if the member has one (it does not today, so none is
  created: no plan asked for one), and the setup README / ARCHITECTURE line for this member.
- `pyproject.toml` minor version bump.

**Out:**

- Copying a Python environment: the widget is stdlib-only.
- Auto-updating the copy when the repo file changes: re-running install refreshes it, as it does
  for agents-workspace-sync and marketplace-updater.

## Phases

### Phase 1

- **Check:** run install on this machine; assert the copy exists, the task action's argument and
  working directory point at the install dir, and the task is `Running` with a `pythonw` process
  whose command line names the copy. Then rename the checkout's `claude_usage_widget.pyw`, run
  `Start-ScheduledTask`, assert a `pythonw` process naming the copy is running again, and rename
  the file back. `ruff check` on the member is unchanged. Uninstall then install again to leave it
  installed.

## Record

- 2026-11-05: Plan reviewed in a fresh context: ready to build, three advisory findings folded in.
- 2026-11-05: Built. `setup/command-center.ps1 install -Member usage-limit-widget` on this
  machine: the task runs `~/.claude-command-center/usage-limit-widget/claude_usage_widget.pyw`
  with that folder as its working directory, and a `pythonw` process names the copy. With the
  checkout's `.pyw` renamed away, `Start-ScheduledTask` replaced the widget (PID 43648 to 11824)
  and the new one runs from the copy. Uninstall removed the task and the folder; install again
  left it running. `ruff check` passes.
