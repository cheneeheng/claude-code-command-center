# file-sync

Keeps a single named file in sync between **two folders you choose at install time**, always
copying from the newer file over the older. One generic engine, two ready-made specializations:

- **CLAUDE.md** — raw copy (plain text, no merge).
- **settings.json** — copy the newer JSON while **preserving machine-specific keys** in the
  destination (e.g. `statusLine.command`).

Each install registers a Windows Task Scheduler task that runs on a configurable interval via a
hidden VBS launcher (missed runs fire on next wake; the schedule never expires). Tasks live under a
`\file-sync\` folder, with a per-(file, folder-pair) task name, so you can install several in
parallel to sync different files or folder pairs at once.

| File | Role | Description |
|------|------|-------------|
| `sync-engine.ps1` | base | Generic newer-wins sync of one file. `-FileA`/`-FileB`, `-Strategy raw\|json-merge`, `-ExcludePaths` (comma-separated, json-merge only; dot-notation with optional `[n]` array indices, e.g. `hooks.PreToolUse[0].hooks[0].command`). |
| `sync-setup.ps1` | base | Generic install/uninstall (Task Scheduler + hidden VBS). Adds `-FileName`, `-Strategy`, `-ExcludePaths` on top of `-FolderA`/`-FolderB`/`-IntervalMinutes`. |
| `claude-md-sync-setup.ps1` | specialization | Thin wrapper fixing `-FileName CLAUDE.md -Strategy raw`. |
| `settings-sync-setup.ps1` | specialization | Thin wrapper fixing `-FileName settings.json -Strategy json-merge` (default exclude `statusLine.command,hooks.PreToolUse[0].hooks[0].command`). |
| `hidden.vbs` | template | Reference copy of the generated launcher. Install writes one `file-sync-<hash>-hidden.vbs` per (file, folder pair) — gitignored, as it embeds resolved local paths. Do not edit manually. |

The two `*-setup.ps1` wrappers are the specializations: each fixes the file name and strategy and
passes `-FolderA`/`-FolderB`/`-IntervalMinutes` through to `sync-setup.ps1`. Call `sync-setup.ps1`
directly to sync any other file.

## Quick start (Windows, as Administrator)

```powershell
# Sync CLAUDE.md across two folders (default 15-min interval):
.\claude-md-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Sync settings.json, preserving machine-specific keys:
.\settings-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Custom interval / extra excluded keys:
.\settings-sync-setup.ps1 -FolderA "C:\a" -FolderB "C:\b" -IntervalMinutes 5 -ExcludePaths "statusLine.command,userId"

# A second, independent sync of a different pair (runs in parallel):
.\claude-md-sync-setup.ps1 -FolderA "C:\proj1\.claude" -FolderB "C:\proj2\.claude"

# Sync any other file directly through the generic setup:
.\sync-setup.ps1 -FileName ".mcp.json" -Strategy raw -FolderA "C:\a" -FolderB "C:\b"

# Remove (pass the same two folders used to install):
.\claude-md-sync-setup.ps1 -Action uninstall -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"
```
