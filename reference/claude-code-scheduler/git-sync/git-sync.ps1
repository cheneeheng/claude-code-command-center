# git-sync.ps1
# Stages all changes in claude-meta, commits with a timestamped message, and pushes.
# Called by scheduler trigger scripts after Claude writes output files.
#
# Parameters:
#   -Label  Short label included in the commit message.
#           e.g. "daily-summary" or "weekly-lessons"
#           Default: "auto"

param(
    [string]$Label = "auto"
)

$ErrorActionPreference = "Stop"

$LogFile = $null

function Log {
    param([string]$Msg)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

$MetaDir = $env:CLAUDE_META_DIR

if (-not $MetaDir) {
    Log "[git-sync] CLAUDE_META_DIR is not set - skipping."
    return
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $ScriptBaseName)

if (-not (Test-Path (Join-Path $MetaDir ".git"))) {
    Log "[git-sync] $MetaDir exists but is not a git repo - skipping."
    Write-Output "           Run 'git init' in $MetaDir, or re-run install.ps1 to initialise it."
    return
}

Push-Location $MetaDir

git add -A

$Staged = git diff --cached --name-only 2>$null
if (-not $Staged) {
    Log "[git-sync] Nothing to commit."
    Pop-Location
    return
}

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$Message   = "${Label}: ${Timestamp}"

git commit -m $Message
Log "[git-sync] Committed: $Message"

$Remote = git remote 2>$null
if ($Remote) {
    git push
    Log "[git-sync] Pushed."
} else {
    Log "[git-sync] No remote configured - commit only."
}

Pop-Location
