# Install/uninstall a settings.json sync (newer wins, excluded keys preserved). Run as Administrator.
# Thin specialization of sync-setup.ps1 — fixes the file name and strategy.
# Usage:
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir>                   # install, 15-min interval
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir> -IntervalMinutes 5
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir> -ExcludePaths "statusLine.command,userId"
#   .\settings-sync-setup.ps1 -Action uninstall -FolderA <dir> -FolderB <dir>
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',
    [string]$FolderA,
    [string]$FolderB,
    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15,
    # Comma-separated dot-notation keys to keep from the destination.
    [string]$ExcludePaths = 'statusLine.command,hooks.PreToolUse[0].hooks[0].command'
)

& "$PSScriptRoot\sync-setup.ps1" `
    -Action $Action -FolderA $FolderA -FolderB $FolderB `
    -IntervalMinutes $IntervalMinutes -FileName 'settings.json' -Strategy json-merge -ExcludePaths $ExcludePaths
