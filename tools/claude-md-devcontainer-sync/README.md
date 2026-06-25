# claude-md-devcontainer-sync

Keeps `CLAUDE.md` in sync between `~/.claude/` and `~/.claude_devcontainer/`, always copying
from the newer file over the older. Plain-text counterpart of `settings-devcontainer-sync` —
no merge logic needed.

| File | Description |
|------|-------------|
| `cc-sync-claude-md-and-claude-devcontainer-md.ps1` | Core sync script. Compares `LastWriteTime` of the two `CLAUDE.md` files and copies the newer over the older. |
| `cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeMd`) running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). Run as Administrator. `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `cc-sync-claude-md-and-claude-devcontainer-md-hidden.vbs` | Generated on install to launch the sync script with no visible window. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1                     # default 15-min interval
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1 -IntervalMinutes 30 # custom interval
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1 -Action uninstall   # remove
```
