#Requires -Version 7.4
# finish-weekly.ps1: the weekly half of finish.
#
#   -Ext <name> -Batch <k>   merge batch k's answer into the master. Exits 0
#                            when the batch is done (merged, nothing new, or
#                            given up), 3 when it is not (run stops there).
#   -Close -Started <epoch> -Trigger <t> -ErrorText <text>
#                            advance each weekly cursor over its done batches,
#                            write last-run-weekly.json, git-sync, clean up.
#
# Cross-reference: src/finish-weekly.sh is the Bash twin.

param(
    [string]$Ext,
    [int]$Batch = -1,
    [switch]$Close,
    [long]$Started,
    [ValidateSet('manual', 'scheduled')][string]$Trigger = 'manual',
    [string]$ErrorText = '',
    [string]$Log
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$attemptsFile = Join-Path $SlState 'attempts.json'
$givenUpFile = Join-Path $SlState 'given-up.txt'

if (-not $Close) {
    $manifestPath = Join-Path $SlStaging "weekly-$Ext/manifest.json"
    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
    $b = $manifest.batches[$Batch]
    if ($b.exit -ne 0) { exit 3 }
    $masterPath = Join-Path $SlMeta $manifest.master
    $masterText = if (Test-Path -LiteralPath $masterPath) { [IO.File]::ReadAllText($masterPath, $script:Utf8) } else { '' }
    $answer = [IO.File]::ReadAllText((Join-Path $SlMeta $b.pending), $script:Utf8)
    $r = Merge-WeeklyAnswer $answer $masterText $manifest.runDate $script:LessonsCategories
    if ($r.Status -eq 'merged') {
        New-Item -ItemType Directory -Force -Path (Split-Path $masterPath) | Out-Null
        Write-Utf8 $masterPath $r.Merged
    }
    if ($r.Status -ne 'invalid') {
        $b.done = $true; $b.added = $r.Added
        Write-Utf8 $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")
        Write-Say "Batch $($Batch + 1): $($r.Added) lesson(s) added."
        exit 0
    }
    $attempts = if (Test-Path -LiteralPath $attemptsFile) { Get-Content -Raw $attemptsFile | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
    $key = "weekly-${Ext}:$($b.files[0])"
    $n = 1 + [int]$attempts[$key]; $attempts[$key] = $n
    Write-Utf8 $attemptsFile (($attempts | ConvertTo-Json -Depth 3) + "`n")
    if ($n -ge [int]$SlConfig.maxAttempts) {
        foreach ($f in $b.files) { [IO.File]::AppendAllText($givenUpFile, "weekly-${Ext}:$f`n", $script:Utf8) }
        $b.done = $true; $b.givenUp = $true; $b.added = 0
        Write-Utf8 $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")
        Write-Say "Gave up on weekly batch $($Batch + 1) after $n invalid answers."
        exit 0
    }
    Write-Say "Batch $($Batch + 1): invalid answer, stopping (retried next run)."
    exit 3
}

# --- close ---------------------------------------------------------------------
$processed = 0; $failed = 0; $given = 0; $results = [ordered]@{}
foreach ($mf in @(Get-ChildItem -Path (Join-Path $SlStaging 'weekly-*/manifest.json') -ErrorAction SilentlyContinue)) {
    $m = Get-Content -Raw $mf.FullName | ConvertFrom-Json -AsHashtable
    $bs = @($m.batches)
    $p = @($bs | Where-Object { $_.exit -eq 0 }).Count
    $f = @($bs | Where-Object { $null -ne $_.exit -and $_.done -ne $true }).Count
    $g = @($bs | Where-Object { $_.givenUp -eq $true }).Count
    $w = 0; foreach ($x in $bs) { $w += [int]$x.added }
    $nn = @($bs | Where-Object { $_.done -eq $true -and $_.givenUp -ne $true -and [int]$_.added -eq 0 }).Count
    if ($m.writeCursor) {
        $firstUndone = -1; for ($i = 0; $i -lt $bs.Count; $i++) { if ($bs[$i].done -ne $true) { $firstUndone = $i; break } }
        $cur = if ($firstUndone -lt 0) { $m.cursorEpoch } elseif ($firstUndone -eq 0) { $null } else { $bs[$firstUndone - 1].cursorEpoch }
        if ($null -ne $cur) { Write-Utf8 (Join-Path $SlState "weekly-$($m.extraction).cursor") "$cur`n" }
    }
    $processed += $p; $failed += $f; $given += $g
    Write-Say "Weekly $($m.extraction): $w lesson(s) added, $p batch(es) answered, $f failed, $g given up."
    $results[$m.extraction] = [ordered]@{ written = $w; none = $nn }
}
if ($ErrorText) { Write-Say "Error: $ErrorText" }

$sync = & (Join-Path $PSScriptRoot 'git-sync.ps1') -Job weekly -Log $script:SlLog

$lastRun = [ordered]@{
    job = 'weekly'; startedAt = $Started; finishedAt = (Get-NowEpoch); trigger = $Trigger
    processed = $processed; results = $results; failed = $failed; givenUp = $given
    deferred = 0; committed = $sync.Committed; pushed = $sync.Pushed
    error = if ($ErrorText) { $ErrorText } else { $null }
}
Write-Utf8 (Join-Path $SlState 'last-run-weekly.json') (($lastRun | ConvertTo-Json -Depth 4) + "`n")

Get-ChildItem -Path (Join-Path $SlStaging 'weekly-*') -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
if ((Test-Path -LiteralPath $SlStaging) -and -not (Get-ChildItem -LiteralPath $SlStaging -Force)) { Remove-Item -Force -LiteralPath $SlStaging }
