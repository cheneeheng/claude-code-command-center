#Requires -Version 7.4
# finish-weekly.ps1: the weekly half of finish.
#
#   -Ext <name> -Batch <k>   merge batch k's answer into the master. Exits 0
#                            when the batch is done (merged, nothing new, or
#                            given up), 3 when it is not (run stops there).
#   -Close -Started <epoch> -Trigger <t> -ErrorText <text> [-QuestionsWarning <text>]
#                            advance each weekly cursor over its done batches,
#                            open new questions and end each replace master
#                            with the fixed When-to-ask section, write
#                            last-run-weekly.json, git-sync, clean up.
#
# Cross-reference: src/finish-weekly.sh is the Bash twin.

param(
    [string]$Ext,
    [int]$Batch = -1,
    [switch]$Close,
    [long]$Started,
    [ValidateSet('manual', 'scheduled')][string]$Trigger = 'manual',
    [string]$ErrorText = '',
    [string]$QuestionsWarning = '',
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
    if ($manifest.mode -eq 'replace') {
        # Replace: mirrors finish-weekly.sh (see the rules there).
        $parts = Split-Answer $answer ([string[]]@('soul', 'questions'))
        $body = Get-SoulBody $(if ($parts.Contains('soul')) { $parts['soul'] } else { '' })
        $lines = ConvertTo-Lines $body
        $first = $lines[0]
        if ($body -and ($first -ceq '# SOUL' -or (Test-Starts $first '# SOUL ')) -and
            $lines -ccontains '## Priorities' -and $lines -ccontains '## Rules' -and
            ($lines.Count - 1) -le [int]$SlConfig.extractions.$Ext.weekly.maxLines) {
            $added = if ($body -ceq (Get-SoulBody $masterText)) { 0 } else { 1 }
            New-Item -ItemType Directory -Force -Path (Split-Path $masterPath) | Out-Null
            Write-Utf8 $masterPath $body
            $q = if ($parts.Contains('questions')) { $parts['questions'] } else { '' }
            if ((ConvertTo-Lines $q) | Where-Object { Test-Starts $_ '### ' }) {
                $qd = Join-Path $SlMeta "$($SlConfig.extractions.$Ext.outputDir)/questions"
                New-Item -ItemType Directory -Force -Path $qd | Out-Null
                Write-Utf8 (Join-Path $qd "$($manifest.runDate)_$($b.cursorEpoch).md") $q
            }
            $b.done = $true; $b.added = $added
            Write-Utf8 $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")
            Write-Say "Batch $($Batch + 1): $(Split-Path -Leaf $masterPath) $(if ($added) { 'updated' } else { 'unchanged' })."
            exit 0
        }
    } else {
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
    if ($m.mode -eq 'replace') {
        Write-Say "Weekly $($m.extraction): $w update(s), $p batch(es) answered, $f failed, $g given up."
        # New questions go out, then the fixed When-to-ask section replaces whatever
        # the master ends with: its issue bullet only when open found a private repo.
        $qrepo = ''
        if ($SlConfig.extractions.($m.extraction).weekly.questions.enabled -eq $true) {
            $q = & (Join-Path $PSScriptRoot 'questions.ps1') open -Ext $m.extraction -Log $script:SlLog
            $qrepo = $q.Repo
            if ($q.Warning) { $QuestionsWarning = if ($QuestionsWarning) { "$QuestionsWarning; $($q.Warning)" } else { $q.Warning } }
        }
        $mp = Join-Path $SlMeta $m.master
        if (Test-Path -LiteralPath $mp) {
            $body = Get-SoulBody ([IO.File]::ReadAllText($mp, $script:Utf8))
            Write-Utf8 $mp ($(if ($body) { "$body`n" } else { '' }) + (Get-AskSection $qrepo $SlConfig.extractions.($m.extraction).weekly.questions.label))
        }
    } else {
        Write-Say "Weekly $($m.extraction): $w lesson(s) added, $p batch(es) answered, $f failed, $g given up."
    }
    $results[$m.extraction] = [ordered]@{ written = $w; none = $nn }
}
if ($ErrorText) { Write-Say "Error: $ErrorText" }

$sync = & (Join-Path $PSScriptRoot 'git-sync.ps1') -Job weekly -Log $script:SlLog
if (-not $ErrorText -and $sync.Error) { $ErrorText = $sync.Error; Write-Say "Error: $ErrorText" }

$lastRun = [ordered]@{
    job = 'weekly'; startedAt = $Started; finishedAt = (Get-NowEpoch); trigger = $Trigger
    processed = $processed; results = $results; failed = $failed; givenUp = $given
    deferred = 0; committed = $sync.Committed; pushed = $sync.Pushed
    error = if ($ErrorText) { $ErrorText } else { $null }
    questionsWarning = if ($QuestionsWarning) { $QuestionsWarning } else { $null }
}
Write-Utf8 (Join-Path $SlState 'last-run-weekly.json') (($lastRun | ConvertTo-Json -Depth 4) + "`n")

Get-ChildItem -Path (Join-Path $SlStaging 'weekly-*') -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
if ((Test-Path -LiteralPath $SlStaging) -and -not (Get-ChildItem -LiteralPath $SlStaging -Force)) { Remove-Item -Force -LiteralPath $SlStaging }
if ($ErrorText) { exit 1 }
exit 0
