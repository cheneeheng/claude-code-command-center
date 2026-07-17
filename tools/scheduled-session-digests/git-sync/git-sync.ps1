# git-sync.ps1
# Stages all changes in claude-meta, commits with a timestamped message, merges the
# current branch back into the default branch if they differ, and pushes.
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

$MetaDir = $env:C4_CLAUDE_META_DIR

if (-not $MetaDir) {
    Log "[git-sync] C4_CLAUDE_META_DIR is not set - skipping."
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

# Run logs (including this script's own) keep being written after the push, so
# tracking them would leave the tree dirty after every run - keep them local-only.
$GitIgnore  = Join-Path $MetaDir ".gitignore"
$IgnoreLine = "/logs/"
if (-not ((Test-Path $GitIgnore) -and ((Get-Content $GitIgnore) -contains $IgnoreLine))) {
    Add-Content -Path $GitIgnore -Value $IgnoreLine -Encoding UTF8
}
git rm -r --cached --ignore-unmatch --quiet logs

git add -A

$Staged = git diff --cached --name-only 2>$null

# Interactive skill runs can start on a feature branch (a branch guard may force
# one before Claude writes files); merge it back so digests always land on the
# default branch.
$Branch  = git branch --show-current
$Default = $null
git show-ref --verify --quiet refs/heads/main
if ($LASTEXITCODE -eq 0) {
    $Default = "main"
} else {
    git show-ref --verify --quiet refs/heads/master
    if ($LASTEXITCODE -eq 0) { $Default = "master" }
}
$NeedsMerge = $Default -and $Branch -and $Branch -ne $Default

if (-not $Staged -and -not $NeedsMerge) {
    Log "[git-sync] Nothing to commit."
    Pop-Location
    return
}

if ($Staged) {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $Message   = "${Label}: ${Timestamp}"

    git commit -m $Message
    Log "[git-sync] Committed: $Message"
} else {
    Log "[git-sync] Nothing to commit."
}

$Merged = $false
if ($NeedsMerge) {
    git checkout --quiet $Default
    git merge --quiet $Branch
    if ($LASTEXITCODE -eq 0) {
        git branch --quiet -d $Branch
        $Merged = $true
        Log "[git-sync] Merged $Branch into $Default and deleted the branch."
    } else {
        if (Test-Path (Join-Path $MetaDir ".git\MERGE_HEAD")) { git merge --abort }
        git checkout --quiet $Branch
        Log "[git-sync] WARNING: could not merge $Branch into $Default - resolve manually."
    }
}

$Remote = git remote 2>$null
if ($Remote) {
    git push
    if ($LASTEXITCODE -eq 0) {
        Log "[git-sync] Pushed."
    } else {
        Log "[git-sync] WARNING: push failed (exit $LASTEXITCODE)."
    }
    # The merged branch may have been pushed by an earlier run; drop the stale copy.
    if ($Merged -and (git ls-remote --heads origin $Branch)) {
        git push --quiet origin --delete $Branch
    }
} else {
    Log "[git-sync] No remote configured - commit only."
}

Pop-Location
