---
title: Launch the sync task through conhost --headless instead of a generated VBS
status: built
created: 2026-10-14
---

## Goal

Each file-sync task today runs `wscript.exe` on a generated `file-sync-<hash>-hidden.vbs`, which
starts `sync-engine.ps1` with a hidden window. This change makes the task start the engine directly
through `conhost.exe --headless`, so no VBS file is generated and the tool no longer depends on
VBScript, which Microsoft has deprecated. What the user sees stays the same: the sync runs on its
interval and no window appears. It also proves the launcher before `scheduled-session-digests`
adopts it.

## Scope

**In:**

- Install registers a task whose action is `conhost.exe --headless powershell.exe ... -File
  sync-engine.ps1` with the same engine arguments the VBS passed.
- Install writes no VBS, and deletes this pair's old `file-sync-<hash>-hidden.vbs` when one exists.
- Uninstall still deletes this pair's old VBS when one exists, so machines installed before this
  change clean up.
- The `hidden.vbs` template is removed, and README, CLAUDE.md, ARCHITECTURE and the root
  `.gitignore` comment describe the conhost launcher.

**Out:**

- `scheduled-session-digests`: it adopts the launcher in its own change, after this one is proven.
- Reinstalling the two live tasks on this machine: they point at the main checkout, so the user
  reinstalls them from `main` after merge. Testing uses a throwaway pair instead.
- The engine, trigger, settings, task naming and wrappers: unchanged.
- Removing the `.gitignore` pattern for generated VBS files: kept, because machines installed
  before this change still have them until they reinstall or uninstall.

## Design

- **Action:** `-Execute conhost.exe -Argument "--headless "<pwsh>" -NonInteractive -NoProfile
  -ExecutionPolicy Bypass -File "<dir>\sync-engine.ps1" -FileA "<a>" -FileB "<b>" -Strategy <s>
  -ExcludePaths "<x>""`, where `<pwsh>` is `(Get-Command pwsh).Source` and `<dir>` is
  `$PSScriptRoot`, both resolved at install time (the VBS resolved the folder at run time from its
  own location). Reason: `--headless` gives pwsh a console that is never shown, while `pwsh
  -WindowStyle Hidden` still flashes because the console exists before pwsh can hide it. Windows
  PowerShell 5.1 is no longer supported, so the engine runs on PowerShell 7.
- **Legacy VBS:** `Get-SyncIdentity` keeps its `VbsPath` field, now used only to delete the old
  file on install and uninstall.
- **Record:** a new ARCHITECTURE Key Decisions entry for the conhost launcher, and the 2026-07-02
  VBS entry's Status becomes `Superseded by 2026-10-14 — conhost --headless launcher`. Its text is
  otherwise kept as history.

## Phases

### Phase 1: Switch the launcher and prove it on a throwaway pair

- **Builds:** the Action and Legacy VBS items in `sync-setup.ps1`.
- **Check:** in a scratch folder, create `a\t.txt` and an older `b\t.txt`, put a fake
  `file-sync-<hash>-hidden.vbs` for that pair next to `sync-setup.ps1`, then run
  `.\sync-setup.ps1 -FileName t.txt -FolderA <a> -FolderB <b>` and `Start-ScheduledTask`. Passing:
  the task's action is `conhost.exe` with `--headless`, `LastTaskResult` is 0, `b\t.txt` now
  matches `a\t.txt`, and the fake VBS is gone. Repeat with `-Strategy json-merge -ExcludePaths
  "k"` on a JSON file to prove the quoted arguments reach the engine (`k` survives in the older
  file). Manual check: the user watches the screen during one `Start-ScheduledTask` and sees no
  window, because no command can observe a window that flashes for a moment. Then uninstall the
  throwaway task.
- **Status:** done. `pwsh -File check-phase1.ps1` (scratchpad) printed `PASS` for raw and
  json-merge (action `conhost.exe --headless`, result 0, synced, VBS removed on install and
  uninstall), and the user saw no window during that run.

### Phase 2: Docs

- **Builds:** the template removal and doc updates from Scope, and the Record items from Design.
- **Check:** `git grep -n -i -E "vbs|wscript" -- tools/file-sync .gitignore` lists only the
  legacy cleanup lines in `sync-setup.ps1`, the superseded ARCHITECTURE entry, the new entry's
  mention of what it replaced, and the kept `.gitignore` pattern with its comment.
- **Status:** done. `git grep -n -i -E "vbs|wscript" -- tools/file-sync .gitignore` lists only
  those, plus the CLAUDE.md invariant naming the legacy cleanup.

## Open

- `conhost.exe --headless` is undocumented by Microsoft. Assumed to work on this machine (Windows
  11, build 26300). Phase 1 proves it or stops the plan.
- Found in Phase 1's red run: `sync-setup.ps1` has no BOM, so Windows PowerShell 5.1 reads it as
  cp1252, and the em dash in uninstall's "not found" message decodes to a closing quote that
  swallows the VBS removal after it. Uninstall under 5.1 never deleted the VBS. The user dropped
  5.1 support; the string is now ASCII anyway, so uninstall cleans up whichever shell runs it.
- Found in Phase 1's first green run: the json-merge case with the one-segment exclude `k` did not
  sync under `powershell.exe`, and did sync once the task ran `pwsh`. So it is 5.1-only (likely
  one-step paths coming back as a scalar under StrictMode), and 5.1 is no longer supported.

## Record

- 2026-10-14 Planned: status ready
- 2026-10-14 Design changed: was "`powershell.exe` stays, matching the current launcher", now "the task runs `pwsh` resolved at install time", because the user dropped Windows PowerShell 5.1 support
- 2026-10-14 Built Phase 1: pwsh -File check-phase1.ps1, PASS (raw and json-merge), no window seen by the user
- 2026-10-14 Built Phase 2: git grep -n -i -E "vbs|wscript" -- tools/file-sync .gitignore, only legacy-cleanup and history mentions remain
- 2026-10-14 PR: #63 https://github.com/cheneeheng/claude-code-command-center/pull/63
- 2026-10-14 Design changed: was "install and uninstall delete a pair's old VBS; the `.gitignore` pattern stays", now "no legacy VBS cleanup and no pattern", because the last VBS installs were reinstalled through setup/ and their files removed
