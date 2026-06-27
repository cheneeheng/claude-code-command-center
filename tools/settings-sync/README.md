# settings-devcontainer-sync

Keeps two `settings.json` files in sync (e.g. `~/.claude/settings.json` and
`~/.claude_devcontainer/settings.json`), always copying from the newer file to the older while
**preserving machine-specific keys** in the destination.

| File | Description |
|------|-------------|
| `cc-sync-claude-settings-and-claude-devcontainer-settings.ps1` | Core sync script. Compares `LastWriteTime`, deep-clones the newer file, strips the configured `ExcludePaths` keys, restores their values from the destination, and writes the result. Default exclude: `statusLine.command`. |
| `cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1` | Install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeSettings`) running on a configurable interval via a hidden VBS launcher (missed runs fire on next wake; schedule never expires). Run as Administrator. `-Action install\|uninstall` (default `install`), `-IntervalMinutes <int>` (default `15`, range `1–1439`). |
| `cc-sync-claude-settings-and-claude-devcontainer-settings-hidden.vbs` | Generated on install to launch the sync script with no visible window. Do not edit manually. |

## Quick start (Windows, as Administrator)

```powershell
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1                     # default 15-min interval
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -IntervalMinutes 5  # custom interval
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -Action uninstall   # remove
```
