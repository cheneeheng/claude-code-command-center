#Requires -Version 7.4
# git-sync.ps1: the only writer of git history in the meta repo. Stages every
# change, makes one commit, and pushes when a remote exists.
# Returns @{ Committed; Pushed; Error }, Error empty when the commit went through.
#
# Cross-reference: src/git-sync.sh is the Bash twin.

param([Parameter(Mandatory)][string]$Job, [string]$Log)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

function Get-FirstLine($Out) { @($Out | ForEach-Object { "$_" } | Where-Object { $_ -match '\S' })[0] }
$committed = $false; $pushed = $false; $err = ''
if (Test-Path -LiteralPath (Join-Path $SlMeta '.git')) {
    # A failed add or commit is the run's error; a failed push is only a warning,
    # because the commit is safe and the next run pushes it.
    $out = git -C $SlMeta add -A 2>&1
    if ($LASTEXITCODE -ne 0) { $err = "git commit failed: $(Get-FirstLine $out)" }
    else {
        git -C $SlMeta diff --cached --quiet
        if ($LASTEXITCODE -ne 0) {
            $out = git -C $SlMeta commit -q -m ("lessons(${Job}): " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>&1
            if ($LASTEXITCODE -eq 0) { $committed = $true } else { $err = "git commit failed: $(Get-FirstLine $out)" }
        }
    }
    if (git -C $SlMeta remote) {
        git -C $SlMeta push -q 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $pushed = $true } else { Write-Say 'git push failed; the commit stays local.' }
    }
}
@{ Committed = $committed; Pushed = $pushed; Error = $err }
