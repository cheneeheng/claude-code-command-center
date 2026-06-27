# settings-sync

Keeps a `settings.json` in sync between **two folders you choose at install time**, always copying
from the newer file to the older while **preserving machine-specific keys** in the destination.

| File | Description |
|------|-------------|
| `settings-sync.ps1` | Core sync script. Compares `LastWriteTime`, deep-clones the newer file, strips the configured `ExcludePaths` keys, restores their values from the destination, and writes the result. Default exclude: `statusLine.command`. Takes `-FileA`/`-FileB`/`-ExcludePaths`. |
| `settings-sync-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeSettings`) running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). Run as Administrator. `-FolderA`/`-FolderB` (the two folders whose `settings.json` to sync; required on install), `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `settings-sync-hidden.vbs` | Generated on install to launch the sync script with no visible window, with the two resolved file paths embedded. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
# Sync the settings.json in two folders (default 15-min interval):
.\settings-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Custom interval:
.\settings-sync-setup.ps1 -FolderA "C:\a" -FolderB "C:\b" -IntervalMinutes 5

# Remove:
.\settings-sync-setup.ps1 -Action uninstall
```
