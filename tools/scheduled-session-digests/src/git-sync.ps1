#Requires -Version 7.4
# git-sync.ps1: the only writer of git history in the meta repo. Stages every
# change, makes one commit, and pushes when a remote exists.
# Returns @{ Committed; Pushed }.
#
# Cross-reference: src/git-sync.sh is the Bash twin.

param([Parameter(Mandatory)][string]$Job, [string]$Log)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$committed = $false; $pushed = $false
if (Test-Path -LiteralPath (Join-Path $SlMeta '.git')) {
    git -C $SlMeta add -A | Out-Null
    git -C $SlMeta diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $SlMeta commit -q -m ("lessons(${Job}): " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) | Out-Null
        $committed = $LASTEXITCODE -eq 0
    }
    if (git -C $SlMeta remote) {
        git -C $SlMeta push -q 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $pushed = $true } else { Write-Say 'git push failed; the commit stays local.' }
    }
}
@{ Committed = $committed; Pushed = $pushed }
