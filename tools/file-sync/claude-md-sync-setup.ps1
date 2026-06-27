# Install/uninstall a CLAUDE.md sync (raw copy, newer wins). Run as Administrator.
# Thin specialization of sync-setup.ps1 — fixes the file name and strategy.
# Usage:
#   .\claude-md-sync-setup.ps1 -FolderA <dir> -FolderB <dir>                  # install, 15-min interval
#   .\claude-md-sync-setup.ps1 -FolderA <dir> -FolderB <dir> -IntervalMinutes 30
#   .\claude-md-sync-setup.ps1 -Action uninstall -FolderA <dir> -FolderB <dir>
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',
    [string]$FolderA,
    [string]$FolderB,
    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15
)

& "$PSScriptRoot\sync-setup.ps1" `
    -Action $Action -FolderA $FolderA -FolderB $FolderB `
    -IntervalMinutes $IntervalMinutes -FileName 'CLAUDE.md' -Strategy raw
