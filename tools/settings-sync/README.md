# settings-sync

Keeps a `settings.json` in sync between **two folders you choose at install time**, always copying
from the newer file to the older while **preserving machine-specific keys** in the destination.

| File | Description |
|------|-------------|
| `settings-sync.ps1` | Core sync script. Compares `LastWriteTime`, deep-clones the newer file, strips the configured `ExcludePaths` keys, restores their values from the destination, and writes the result. Default exclude: `statusLine.command`. Takes `-FileA`/`-FileB`/`-ExcludePaths`. |
| `settings-sync-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). The task lives under a folder named after this tool (`\settings-sync\`), with a per-pair task name derived from the two folders, so you can install several in parallel to sync different folder pairs at once. Run as Administrator. `-FolderA`/`-FolderB` (the two folders whose `settings.json` to sync; required for **both** install and uninstall), `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `settings-sync-hidden.vbs` | A generated hidden VBS launcher (one per synced folder pair, named `settings-sync-<hash>-hidden.vbs`) that runs the sync script with no visible window and the two resolved file paths embedded. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
# Sync the settings.json in two folders (default 15-min interval):
.\settings-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Custom interval:
.\settings-sync-setup.ps1 -FolderA "C:\a" -FolderB "C:\b" -IntervalMinutes 5

# Install a second, independent sync of a different pair (runs in parallel):
.\settings-sync-setup.ps1 -FolderA "C:\proj1\.claude" -FolderB "C:\proj2\.claude"

# Remove (pass the same two folders used to install):
.\settings-sync-setup.ps1 -Action uninstall -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"
```
