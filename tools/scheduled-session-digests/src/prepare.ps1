#Requires -Version 7.2
# prepare.ps1: scans Claude Code sessions, cleans each transcript, and archives
# it under transcripts/. Single owner of scanning, filtering, cleanup, and
# archiving. Called by run.ps1.
#
# Cross-reference: src/prepare.sh is the Bash twin.

param(
    [Parameter(Mandatory)][long]$Cutoff,
    [switch]$ArchiveOnly,
    [string]$MetaDir
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons $MetaDir
if (-not $ArchiveOnly) { throw 'prepare: only -ArchiveOnly is built so far' }

$minTurns = [int]$SlConfig.thresholds.minUserTurns
$minChars = [int]$SlConfig.thresholds.minTranscriptChars
$upper = (Get-NowEpoch) - [long]$SlConfig.settleMinutes * 60
$metaProject = ConvertTo-ProjectDirName $SlMeta

# --- scan (rules 1-3) ----------------------------------------------------------
$found = [System.Collections.Generic.List[object]]::new()
foreach ($root in $SlInstall.scanRoots) {
    $projects = Join-Path $root 'projects'
    if (-not (Test-Path -LiteralPath $projects -PathType Container)) { continue }
    foreach ($dir in Get-ChildItem -LiteralPath $projects -Directory) {
        if ($dir.Name -ceq $metaProject) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.jsonl') {
            if ($f.FullName -match '[/\\]subagents[/\\]') { continue }
            $first = [IO.File]::ReadLines($f.FullName) | Select-Object -First 1
            try {
                $j = [System.Text.Json.JsonDocument]::Parse($first).RootElement
                if (Test-True (Get-Prop $j 'isSidechain')) { continue }
            } catch {}
            $m = Get-MtimeEpoch $f
            if ($m -le $Cutoff -or $m -gt $upper) { continue }
            $found.Add([pscustomobject]@{ Mtime = $m; Uuid = $f.BaseName; Path = $f.FullName })
        }
    }
}
# Sorted by mtime, then file name, bytewise (matches Bash `LC_ALL=C sort`).
$keys = [string[]]@($found | ForEach-Object { '{0:D12} {1}' -f $_.Mtime, $_.Uuid })
$items = $found.ToArray()
[Array]::Sort($keys, $items, [StringComparer]::Ordinal)

# --- archive (rule 7) ----------------------------------------------------------
$transcripts = Join-Path $SlMeta 'transcripts'
$archived = 0; $skipped = 0
foreach ($c in $items) {
    $t = Convert-Transcript $c.Path
    if ($t.Turns -lt $minTurns -or (Get-CodePointLength $t.Body) -lt $minChars) { $skipped++; continue }
    $date = Get-LocalDate $c.Mtime
    $dest = $null
    if (Test-Path -LiteralPath $transcripts) {
        $dest = Get-ChildItem -LiteralPath $transcripts -Recurse -File -Filter "*_$($c.Uuid).md" |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $dest) { $dest = Join-Path $transcripts "$($date.Substring(0,4))/$($date.Substring(5,2))/$($date)_$($c.Uuid).md" }
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    $title = if ($null -ne $t.Title) { $t.Title } else { $c.Uuid }
    Write-Utf8 $dest ("# Session Transcript`nUUID: $($c.Uuid)`nDate: $date`nTitle: $title`nProject: $($t.Project)`nCleanup: v1`n`n## Conversation`n`n" + $t.Body)
    $archived++
}

Write-Output "Archived $archived session(s), skipped $skipped (too short)."
