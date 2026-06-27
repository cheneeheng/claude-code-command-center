# claude-md-sync

Keeps a `CLAUDE.md` in sync between **two folders you choose at install time**, always copying
from the newer file over the older. Plain-text counterpart of `settings-sync` —
no merge logic needed.

| File | Description |
|------|-------------|
| `claude-md-sync.ps1` | Core sync script. Compares `LastWriteTime` of the two `CLAUDE.md` files and copies the newer over the older. Takes `-FileA`/`-FileB`. |
| `claude-md-sync-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). The task lives under a folder named after this tool (`\claude-md-sync\`), with a per-pair task name derived from the two folders, so you can install several in parallel to sync different folder pairs at once. Run as Administrator. `-FolderA`/`-FolderB` (the two folders whose `CLAUDE.md` to sync; required for **both** install and uninstall), `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `claude-md-sync-hidden.vbs` | A generated hidden VBS launcher (one per synced folder pair, named `claude-md-sync-<hash>-hidden.vbs`) that runs the sync script with no visible window and the two resolved file paths embedded. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
# Sync the CLAUDE.md in two folders (default 15-min interval):
.\claude-md-sync-setup.ps1 -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"

# Custom interval:
.\claude-md-sync-setup.ps1 -FolderA "C:\a" -FolderB "C:\b" -IntervalMinutes 30

# Install a second, independent sync of a different pair (runs in parallel):
.\claude-md-sync-setup.ps1 -FolderA "C:\proj1\.claude" -FolderB "C:\proj2\.claude"

# Remove (pass the same two folders used to install):
.\claude-md-sync-setup.ps1 -Action uninstall -FolderA "$env:USERPROFILE\.claude" -FolderB "$env:USERPROFILE\.claude_mirror"
```
