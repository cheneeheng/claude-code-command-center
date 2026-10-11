#Requires -Version 7.2
# run.ps1: the only consumer of the pipeline. Takes the lock, works out the
# scan cutoff, and drives prepare (and, from Phase 2, claude and finish).
#
# Cross-reference: src/run.sh is the Bash twin.

param(
    [string]$MetaDir,
    [switch]$All,
    [string]$Since,
    [switch]$ArchiveOnly
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons $MetaDir
if (-not $ArchiveOnly) { Write-Error 'run: only -ArchiveOnly is built so far'; exit 1 }

Enter-Lock
try {
    # Cutoff: -All is 0, -Since is that local date's midnight, otherwise the
    # stored cursor, or now - firstRunDays when there is none. -ArchiveOnly
    # never writes a cursor.
    $cursorFile = Join-Path $SlState 'daily.cursor'
    $cutoff = if ($All) { 0 }
        elseif ($Since) { [DateTimeOffset]::new([DateTime]::ParseExact($Since, 'yyyy-MM-dd', $null)).ToUnixTimeSeconds() }
        elseif (Test-Path -LiteralPath $cursorFile) { [long](Get-Content -Raw $cursorFile).Trim() }
        else { (Get-NowEpoch) - [long]$SlConfig.firstRunDays * 86400 }

    & (Join-Path $PSScriptRoot 'prepare.ps1') -Cutoff $cutoff -ArchiveOnly -MetaDir $SlMeta
} finally {
    Exit-Lock
}
