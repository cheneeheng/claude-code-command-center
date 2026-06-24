# install.ps1 - git-sync utility
#
# Copies git-sync.ps1 to %USERPROFILE%\claude-meta\.claude\scripts\.
# The daily-summary and weekly-lessons installers call this automatically,
# but you can also run it standalone to update the script in place.

param()

$ErrorActionPreference = "Stop"
$Here    = $PSScriptRoot
$MetaDir = Join-Path $env:USERPROFILE "claude-meta"
$Dest    = Join-Path $MetaDir ".claude\scripts"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item "$Here\git-sync.ps1" -Destination "$Dest\git-sync.ps1" -Force

Write-Host "Installed: $Dest\git-sync.ps1" -ForegroundColor Green
