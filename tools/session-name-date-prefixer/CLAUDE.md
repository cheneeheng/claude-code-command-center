# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code `SessionStart` hook (matcher `startup|clear`) that sets each new session's title to
`<cwd leaf>-<yyMMddHHmm>`, unless the user already named it. The setup scripts write it into
`settings.json`.

## Running

See README.md for install/uninstall. Files:

- `session-name-date-prefixer-setup.ps1` — Windows: writes the PowerShell hook (`"shell": "powershell"`).
- `session-name-date-prefixer-setup.sh` — Linux/macOS: writes the bash hook. Needs `jq`.
- `tests/smoke.sh` — `bash tests/smoke.sh`; CI runs it on Ubuntu and Windows.

## Invariants — do not break these

- **Only name a session the user did not name.** The hook prints nothing when its input has a
  `session_title` (set by `--name`, `/rename`, or another hook), except one in the hook's own
  `<cwd leaf>-<10 digits>` form: `/clear` inherits the old session's title, so that one is
  replaced. A user name in exactly that form is replaced too.
- **Touch only our hook.** Install and uninstall find it by the `session-name-date-prefixer`
  no-op at the start of its command, and keep every other key and hook. Re-running install leaves
  exactly one.
- **`SessionStart` stays a JSON array.** In the `.ps1`, wrap filtered lists in `@()`: a one-item
  `Where-Object` result is a single object, and `ConvertTo-Json` would write it as an object.
- **The PowerShell command must run in both Windows PowerShell 5.1 and pwsh**, because the docs do
  not say which one `"shell": "powershell"` starts.
- **Keep the two hook commands behaviourally identical:** same title format, same folder-name
  cleanup (anything outside `[A-Za-z0-9_-]` becomes `-`), same skip rule.
- **Matcher `startup|clear`:** the user wants a fresh title after `/clear` too. The hooks docs list
  `sessionTitle` for `startup`, `resume` and `fork` only, so whether `clear` applies it is checked
  live, not by the smoke test.

## Conventions

- PowerShell + Bash tool; no Python, no dependencies beyond `jq` for the bash setup.
- Also installable via the repo-wide `setup/` orchestrator.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
