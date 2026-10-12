#Requires -Version 7.4
# prepare.ps1: scans Claude Code sessions, cleans each transcript, archives it
# under transcripts/, and stages the sessions that still need an extraction.
# Single owner of scanning, filtering, cleanup, archiving, and staging.
#
#   -Mode archive  archive only (no staging, no cursor)
#   -Mode dry      print the preview, write nothing
#   -Mode stage    archive, then stage jobs and write staging/daily/manifest.json
#
# Cross-reference: src/prepare.sh is the Bash twin.

param(
    [Parameter(Mandatory)][long]$Cutoff,
    [Parameter(Mandatory)][ValidateSet('archive', 'dry', 'stage')][string]$Mode,
    [int]$Cap = 0,
    [switch]$WriteCursor,
    [string]$Log
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$minTurns = [int]$SlConfig.thresholds.minUserTurns
$minChars = [int]$SlConfig.thresholds.minTranscriptChars
$upper = (Get-NowEpoch) - [long]$SlConfig.settleMinutes * 60
$metaProject = ConvertTo-ProjectDirName $SlMeta
$givenUpFile = Join-Path $SlState 'given-up.txt'
$dir = Join-Path $SlStaging 'daily'

# --- scan (rules 1-3) ----------------------------------------------------------
$found = [System.Collections.Generic.List[object]]::new()
foreach ($root in $SlInstall.scanRoots) {
    $projects = Join-Path $root 'projects'
    if (-not (Test-Path -LiteralPath $projects -PathType Container)) { continue }
    foreach ($d in Get-ChildItem -LiteralPath $projects -Directory) {
        if ($d.Name -ceq $metaProject) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Filter '*.jsonl') {
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
# Only the keys are sorted (PowerShell binds [Array]::Sort(keys, items) to an
# overload that leaves items alone); each key carries its item's index.
$keys = [string[]]@(for ($i = 0; $i -lt $found.Count; $i++) { '{0:D12} {1} {2}' -f $found[$i].Mtime, $found[$i].Uuid, $i })
[Array]::Sort($keys, [StringComparer]::Ordinal)
$items = @($keys | ForEach-Object { $found[[int]($_ -split ' ')[-1]] })

# --- what each session still needs (rule 4) ----------------------------------
# An extraction is done for a session when its outputDir holds a file named
# <date>_<uuid>[_<title>].md, or "<extraction>:<uuid>" is in given-up.txt.
$done = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$exts = [System.Collections.Generic.List[string]]::new(); $outDir = @{}
foreach ($p in $SlConfig.extractions.PSObject.Properties) {
    if (-not $p.Value.enabled) { continue }
    $exts.Add($p.Name); $outDir[$p.Name] = $p.Value.outputDir
    $od = Join-Path $SlMeta $p.Value.outputDir
    if (Test-Path -LiteralPath $od) {
        foreach ($f in Get-ChildItem -LiteralPath $od -Recurse -File -Filter '*.md') {
            $rest = $f.BaseName.Substring($f.BaseName.IndexOf('_') + 1)
            [void]$done.Add("$($p.Name):" + $rest.Split('_')[0])
        }
    }
}
if (Test-Path -LiteralPath $givenUpFile) {
    foreach ($k in Get-Content -LiteralPath $givenUpFile) { if ($k) { [void]$done.Add($k) } }
}

if ($Mode -eq 'stage') {
    if (Test-Path -LiteralPath $dir) { Remove-Item -Recurse -Force -LiteralPath $dir }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'in'), (Join-Path $dir 'out') | Out-Null
}

$archived = 0; $skipped = 0; $newest = $Cutoff
$jobs = [System.Collections.Generic.List[object]]::new()
$transcripts = Join-Path $SlMeta 'transcripts'
foreach ($c in $items) {
    $newest = $c.Mtime
    $t = Convert-Transcript $c.Path
    if ($t.Turns -lt $minTurns -or (Get-CodePointLength $t.Body) -lt $minChars) { $skipped++; continue }

    $date = Get-LocalDate $c.Mtime
    $title = if ($null -ne $t.Title) { $t.Title } else { $c.Uuid }
    $text = "# Session Transcript`nUUID: $($c.Uuid)`nDate: $date`nTitle: $title`nProject: $($t.Project)`nCleanup: v1`n`n## Conversation`n`n" + $t.Body

    # Rule 7: archive every candidate that passes the thresholds.
    $rel = ''
    if ($Mode -ne 'dry') {
        if (Test-Path -LiteralPath $transcripts) {
            $hit = Get-ChildItem -LiteralPath $transcripts -Recurse -File -Filter "*_$($c.Uuid).md" | Select-Object -First 1
            if ($hit) { $rel = [IO.Path]::GetRelativePath($SlMeta, $hit.FullName) -replace '\\', '/' }
        }
        if (-not $rel) { $rel = "transcripts/$($date.Substring(0,4))/$($date.Substring(5,2))/$($date)_$($c.Uuid).md" }
        $abs = Join-Path $SlMeta $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $abs) | Out-Null
        Write-Utf8 $abs $text
        $archived++
    }
    if ($Mode -eq 'archive') { continue }

    $needed = @($exts | Where-Object { -not $done.Contains("${_}:$($c.Uuid)") })
    if ($needed.Count -eq 0) { $skipped++; continue }

    $suffix = if ($null -ne $t.Title) { '_' + (Get-SafeTitle $t.Title) } else { '' }
    $outputs = [ordered]@{}
    foreach ($e in $needed) {
        $outputs[$e] = "$($outDir[$e])/$($date.Substring(0,4))/$($date.Substring(5,2))/$($date)_$($c.Uuid)$suffix.md"
    }
    if ($Mode -eq 'stage') { Write-Utf8 (Join-Path $dir "in/$($c.Uuid).md") $text }
    $jobs.Add([pscustomobject][ordered]@{
        uuid = $c.Uuid; date = $date; title = $title; project = $t.Project; mtime = $c.Mtime
        input = ".claude/session-lessons/staging/daily/in/$($c.Uuid).md"; archive = $rel
        pending = ".claude/session-lessons/staging/daily/out/$($c.Uuid).md"; exit = $null
        needed = [string[]]$needed; outputs = $outputs; chars = (Get-CodePointLength $text)
    })
}

if ($Mode -eq 'archive') {
    Write-Output "Archived $archived session(s), skipped $skipped (too short)."
    exit 0
}

# The cap. A group of sessions with the same mtime second is never split:
# staging stops before a group that would cross the cap, except that a first
# group larger than the cap is staged whole.
$staged = $jobs.ToArray()
if ($Cap -gt 0 -and $jobs.Count -gt $Cap) {
    $take = [System.Collections.Generic.List[object]]::new()
    $i = 0
    while ($i -lt $jobs.Count) {
        $j = $i; while ($j -lt $jobs.Count -and $jobs[$j].mtime -eq $jobs[$i].mtime) { $j++ }
        if ($take.Count -eq 0 -or $take.Count + ($j - $i) -le $Cap) { for ($k = $i; $k -lt $j; $k++) { $take.Add($jobs[$k]) } }
        else { break }
        $i = $j
    }
    $staged = $take.ToArray()
}
$since = if ($Cutoff -gt 0) { Get-LocalDate $Cutoff } else { 'the beginning' }
$tokens = [long][Math]::Floor((($staged | Measure-Object -Property chars -Sum).Sum) / 4)
$deferred = $jobs.Count - $staged.Count

Write-Say "Daily run: $($staged.Count) session(s) to process, since $since."
Write-Say "Skipped $skipped (too short or done), deferred $deferred, about $tokens tokens (rough)."

if ($Mode -eq 'stage') {
    $keep = [System.Collections.Generic.HashSet[string]]::new([string[]]@($staged | ForEach-Object uuid))
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $dir 'in') -File) { if (-not $keep.Contains($f.BaseName)) { Remove-Item -LiteralPath $f.FullName } }
    $manifest = [ordered]@{
        job = 'daily'; cursorFile = '.claude/session-lessons/state/daily.cursor'
        cutoffEpoch = $Cutoff
        cursorEpoch = if ($staged.Count -lt $jobs.Count) { $staged[-1].mtime } else { $newest }
        writeCursor = [bool]$WriteCursor; since = $since; skipped = $skipped; deferred = $deferred
        approxTokens = $tokens
        jobs = @($staged | Select-Object -Property * -ExcludeProperty chars)
    }
    Write-Utf8 (Join-Path $dir 'manifest.json') (($manifest | ConvertTo-Json -Depth 6) + "`n")
}
