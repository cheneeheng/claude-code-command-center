---
title: session-name-date-prefixer, name sessions with a SessionStart hook instead of a claude wrapper
status: built
created: 2026-11-05
---

## Goal

Replace the `claude` PATH wrapper with a Claude Code `SessionStart` hook that sets the session
title to `<folder>-<yyMMddHHmm>`. The setup script writes the hook into the user's
`settings.json`, so nothing sits in front of the real `claude` binary. The flow that matters:
the user runs setup once, then every new `claude` session in any folder gets a dated title, and a
session started with `--name` keeps the name the user gave.

## Scope

**In:**

- A `SessionStart` hook, matcher `startup`, whose output sets `hookSpecificOutput.sessionTitle`.
- Two versions of the hook command, one per OS family (the user asked for a command valid on both,
  or two versions if not possible, see Design).
- `session-name-date-prefixer-setup.ps1` / `.sh` rewritten: install merges the hook into
  `settings.json`, uninstall removes only that hook, both keep every other key and hook.
- One-time removal of the old wrapper and its PATH edit on install and uninstall, so the old and
  new mechanisms never both run.
- A smoke test run in CI on Ubuntu and Windows.
- `setup/` kept in step: the `Detect` probe, setup's README row.

**Out:**

- `clear` in the matcher: Claude Code applies `sessionTitle` only when `source` is `startup`,
  `resume`, or `fork` (hooks docs, SessionStart decision control), so on `clear` it does nothing.
- `resume` and `fork`: a resumed session keeps its title. A fork is out until someone asks.
- A `-ClaudeDir` loop over several config dirs: the statusline-hook `instances` shape is not asked for.

## Design

- **Why two versions:** a hook command with no `shell` field runs in Git Bash on Windows, but in
  PowerShell when Git Bash is not installed (hooks docs, command hook fields), where `printf`,
  `basename` and `date +%y...` fail. No single command line is valid in both bash and PowerShell
  without polyglot tricks. So the Windows setup (`.ps1`) writes a PowerShell command with
  `"shell": "powershell"`, which runs wherever Claude Code runs on Windows, and the Linux/macOS
  setup (`.sh`) writes a bash command.
- **Bash command:**

  ```sh
  : session-name-date-prefixer; grep -q '"session_title"' || printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"%s-%s"}}' "$(basename "$PWD" | tr -c 'A-Za-z0-9_\n-' '-')" "$(date +%y%m%d%H%M)"
  ```

- **PowerShell command** (valid in Windows PowerShell 5.1 and PowerShell 7, since the docs do not
  say which one `"shell": "powershell"` starts):

  ```powershell
  $null = 'session-name-date-prefixer'; if (-not ([Console]::In.ReadToEnd() | ConvertFrom-Json).session_title) { '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"' + ((Split-Path -Leaf (Get-Location)) -replace '[^A-Za-z0-9_-]', '-') + '-' + (Get-Date -Format yyMMddHHmm) + '"}}' }
  ```

- **Respecting `--name`:** the hook input carries `session_title` when a title was already set
  with `--name`, `/rename`, or a hook (hooks docs, SessionStart input). Both commands print nothing
  when it is present, which keeps the wrapper's rule: only name a session the user did not name.
- **Folder name cleanup:** anything outside `[A-Za-z0-9_-]` becomes `-`, one dash per character,
  as the old `.ps1` wrapper did (the old `.sh` wrapper also squeezed runs of dashes; both versions
  now match the `.ps1`). It also keeps the hand-built JSON valid: a quote or backslash in a folder
  name cannot reach it. A session started at a filesystem root gets `-<stamp>` (bash `--<stamp>`):
  accepted, nobody names a project after `/`.
- **Marker:** both commands start with a no-op statement naming the tool
  (`: session-name-date-prefixer;` in bash, `$null = 'session-name-date-prefixer';` in PowerShell),
  not a trailing comment, which would swallow a closing brace if Claude Code ever wraps the command.
  Install and uninstall find the hook by that text in a `SessionStart` entry's `command`, so they never touch a
  hook the user wrote.
- **Install:** read `settings.json` (missing or blank is `{}`), drop every `SessionStart` matcher
  group whose hooks include the marker, append one group
  `{"matcher": "startup", "hooks": [{"type": "command", "shell": "powershell", "command": ...}]}`
  (no `shell` key in the bash version), save. Re-running install leaves exactly one group.
  `-ClaudeDir` (`.ps1`) / `--claude-dir` (`.sh`) picks the config dir, default `~/.claude`, the
  same as statusline-hook. In `.ps1` every filtered list is wrapped in `@()`, because a one-item
  `Where-Object` result is a single object and `ConvertTo-Json` would write `SessionStart` as an
  object instead of an array, corrupting the user's other hooks.
- **Uninstall:** drop the marked groups. If `SessionStart` is then empty, drop it, and if `hooks`
  is then empty, drop that too, so an install plus uninstall on a file with no hooks restores the
  file's keys.
- **JSON editing:** `.ps1` uses `ConvertFrom-Json` / `ConvertTo-Json -Depth 20`, `.sh` uses `jq`,
  the same as statusline-hook-setup. `.sh` exits with a message when `jq` is missing.
- **Old wrapper cleanup:** `.ps1` deletes `%LOCALAPPDATA%\claude-automation\cc-inject-date-to-session-name`
  (the wrapper's own folder) and removes exactly that entry from the user PATH. `.sh` deletes
  `~/.local/bin/claude` only when it contains the wrapper's `auto-injects --name` text, the same
  check the old uninstall used. It leaves the `# Added by claude wrapper install` rc line alone:
  that line puts `~/.local/bin` on PATH, where Claude Code's native installer, pipx and uv tools
  also live, so removing it could hide `claude` itself. Each step prints what it did, or that
  there was nothing to do.
- **Files:** `session-name-date-prefixer.ps1` and `.sh` (the wrappers) are deleted. The commands
  live in the setup scripts, since the hook is one line and needs no installed file.
- **setup/:** `Detect` becomes "the default `settings.json` contains the marker". Install and
  uninstall calls are unchanged (same script names, same `-Action`). The setup README row changes
  from "Adds a `claude` wrapper to your user PATH" to "Adds a SessionStart hook to `settings.json`
  that names each new session".
- **Version:** `VERSION` 0.2.0 to 0.3.0. The member has no `CHANGELOG.md`, so none is added.

## Phases

### Phase 1: the hook commands and the setup scripts

- Rewrite both setup scripts as above, delete both wrappers.
- **Check:** `tests/smoke.sh`, run with `bash tests/smoke.sh`, which for the setup of the current
  OS family (both on Windows, where Git Bash and pwsh exist; `.sh` only elsewhere) and with a temp
  config dir:
  0. Points `HOME` and (Windows) `LOCALAPPDATA` at temp dirs and seeds a fake old wrapper
     (`.ps1`: the wrapper folder; `.sh`: `~/.local/bin/claude` holding `auto-injects --name`).
     The user PATH edit only removes the entry equal to the temp wrapper folder, so the real one is
     never touched.
  1. Seeds `settings.json` with an unrelated key and an unrelated `SessionStart` hook.
  2. Installs twice, then asserts one marked group, the unrelated key and hook intact,
     `.hooks.SessionStart` still an array, and the fake old wrapper gone.
  3. Runs the installed command (`bash -c` for the bash version; `powershell -NoProfile -Command`
     and `pwsh -NoProfile -Command` for the PowerShell one) from a folder named `my proj`, with
     stdin `{}`, and asserts the output parses as JSON whose `sessionTitle` matches
     `^my-proj-[0-9]{10}$`.
  4. Runs it with stdin `{"session_title":"mine"}` and asserts empty output.
  5. Uninstalls and asserts no marker, the unrelated key and hook intact, `.hooks.SessionStart`
     still an array.

### Phase 2: CI, docs, setup/

- `.github/workflows/session-name-date-prefixer.yml`: the smoke test on `ubuntu-latest` and
  `windows-latest`, no path filter, as `statusline.yml` does.
- README, CLAUDE.md (invariants rewritten for the hook), `product/ARCHITECTURE.md` (diagrams and a
  Key Decision that supersedes the 2026-07-02 "PATH shim, not a hook" decision, whose context
  "no hook fires before session naming" no longer holds).
- `setup/registry.ps1` `Detect`, `setup/README.md` row. Checked and needing no change:
  `setup/product/ARCHITECTURE.md` (a node named after the member), the config example (`{}`), the
  root README row ("Prefix ... with the date", still true), and `docs/automation-suite.md` (a
  historical overview of the original suite).
- **Check:** smoke test green on both runners in the PR; `pwsh -Command` parse of
  `setup/registry.ps1`.

## Risks

- **Making the check required:** the session's token cannot read branch protection (HTTP 403),
  so the user adds the new job as a required check.
- **Live title:** the smoke test proves the hook's output, not that Claude Code renders it or how
  it passes the command to the shell. The user confirms in one new session after merge.

## Record

- 2026-11-05: Plan reviewed in a fresh context: one blocking finding (one-item `Where-Object`
  results serialise `SessionStart` as an object) and seven advisory ones, all folded in above.
- 2026-11-05: Phases 1 and 2 built. `bash tests/smoke.sh` on Windows passes for sh/bash,
  ps1/pwsh and ps1/powershell. With `$groups[0]` swapped in for the array, the smoke test fails
  with "uninstall damaged other settings", so it catches the blocking finding's bug.
