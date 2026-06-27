# claude-md-sync

Keeps a `CLAUDE.md` in sync between **two folders you choose at install time**, always copying
from the newer file over the older. Plain-text counterpart of `settings-sync` —
no merge logic needed.

| File | Description |
|------|-------------|
| `claude-md-sync.ps1` | Core sync script. Compares `LastWriteTime` of the two `CLAUDE.md` files and copies the newer over the older. Takes `-FileA`/`-FileB`. |
| `claude-md-sync-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeMd`) running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). Run as Administrator. `-FolderA`/`-FolderB` (the two folders whose `CLAUDE.md` to sync; required on install), `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `claude-md-sync-hidden.vbs` | Generated on install to launch the sync script with no visible window, with the two resolved file paths embedded. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
# Sync the CLAUDE.md in two folders (default 15-min interval):
.\claude-md-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Custom interval:
.\claude-md-sync-setup.ps1 -FolderA "C:\a" -FolderB "C:\b" -IntervalMinutes 30

# Remove:
.\claude-md-sync-setup.ps1 -Action uninstall
```
