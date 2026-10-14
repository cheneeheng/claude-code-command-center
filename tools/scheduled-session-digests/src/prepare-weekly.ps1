#Requires -Version 7.4
# prepare-weekly.ps1: stages the weekly merge for one extraction. Collects the
# per-session files written since the cursor, skips no-content stubs and
# given-up files, and splits them into batches, each with the master's
# existing titles. Writes staging/weekly-<ext>/manifest.json in stage mode.
#
# Cross-reference: src/prepare-weekly.sh is the Bash twin.

param(
    [Parameter(Mandatory)][string]$Ext,
    [Parameter(Mandatory)][long]$Cutoff,
    [Parameter(Mandatory)][ValidateSet('dry', 'stage')][string]$Mode,
    [switch]$WriteCursor,
    [string]$Log
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$e = $SlConfig.extractions.$Ext
$outDir = $e.outputDir; $master = $e.weekly.master
# append: the master gains new entries (lessons). replace: claude rewrites the
# whole master (decisions' SOUL.md); run puts its current text where the
# {{CURRENT_FILE}} line is, just before each call.
$wmode = if ($e.weekly.mode) { $e.weekly.mode } else { 'append' }
$limit = [long]$SlConfig.weeklyBatchChars
$dir = Join-Path $SlStaging "weekly-$Ext"
$runDate = Get-Date -Format 'yyyy-MM-dd'
$givenUpFile = Join-Path $SlState 'given-up.txt'
$gone = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
if (Test-Path -LiteralPath $givenUpFile) { foreach ($k in Get-Content -LiteralPath $givenUpFile) { if ($k) { [void]$gone.Add($k) } } }

# Candidates by mtime, then meta-relative path (bytewise). Only the keys are
# sorted; each carries its item's index (see prepare.ps1).
$found = [System.Collections.Generic.List[object]]::new()
$od = Join-Path $SlMeta $outDir
if (Test-Path -LiteralPath $od) {
    foreach ($f in Get-ChildItem -LiteralPath $od -Recurse -File -Filter '*.md') {
        $m = Get-MtimeEpoch $f
        if ($m -le $Cutoff) { continue }
        $rel = [IO.Path]::GetRelativePath($SlMeta, $f.FullName) -replace '\\', '/'
        if (Test-Starts $rel "$outDir/questions/") { continue }
        $found.Add([pscustomobject]@{ Mtime = $m; Rel = $rel; Path = $f.FullName })
    }
}
$keys = [string[]]@(for ($i = 0; $i -lt $found.Count; $i++) { '{0:D12} {1}{2}{3}' -f $found[$i].Mtime, $found[$i].Rel, [char]0, $i })
[Array]::Sort($keys, [StringComparer]::Ordinal)
$items = @($keys | ForEach-Object { $found[[int]($_ -split [char]0)[-1]] })

$newest = $Cutoff
$files = [System.Collections.Generic.List[object]]::new()
foreach ($c in $items) {
    $newest = $c.Mtime
    if ($gone.Contains("weekly-${Ext}:$($c.Rel)")) { continue }
    if ($e.none -and [IO.File]::ReadAllText($c.Path, $script:Utf8).Contains($e.none)) { continue }
    $files.Add($c)
}

# What precedes the new files. append: the master's titles, grouped under their
# headings. replace: the current-file slot, then every "### " question title in
# <outputDir>/questions/*.md (by file name, first occurrence) that no
# <outputDir>/answered/issue-*.md answers (its first line is "## <title>").
if ($wmode -eq 'replace') {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ad = Join-Path $SlMeta "$outDir/answered"
    if (Test-Path -LiteralPath $ad) {
        foreach ($f in Get-ChildItem -LiteralPath $ad -File -Filter 'issue-*.md') {
            $first = (ConvertTo-Lines ([IO.File]::ReadAllText($f.FullName, $script:Utf8)))[0]
            [void]$seen.Add('### ' + $(if (Test-Starts $first '## ') { $first.Substring(3) } else { $first }))
        }
    }
    $open = [System.Collections.Generic.List[string]]::new()
    $qd = Join-Path $SlMeta "$outDir/questions"
    if (Test-Path -LiteralPath $qd) {
        $names = [string[]]@(Get-ChildItem -LiteralPath $qd -File -Filter '*.md' | ForEach-Object Name)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        foreach ($n in $names) {
            foreach ($l in (ConvertTo-Lines ([IO.File]::ReadAllText((Join-Path $qd $n), $script:Utf8)))) {
                if ((Test-Starts $l '### ') -and $seen.Add($l)) { $open.Add($l) }
            }
        }
    }
    $headText = "# Current file`n`n{{CURRENT_FILE}}`n`n# Open questions`n`n" + $(if ($open.Count) { $open -join "`n" } else { '(none)' })
} else {
    $titles = '(none yet)'
    $mp = Join-Path $SlMeta $master
    if (Test-Path -LiteralPath $mp) {
        $t = @((ConvertTo-Lines ([IO.File]::ReadAllText($mp, $script:Utf8))) | Where-Object { (Test-Starts $_ '## ') -or (Test-Starts $_ '### ') })
        if ($t.Count) { $titles = $t -join "`n" }
    }
    $headText = "# Existing titles`n`n$titles"
}

# One file's section: "## Source: <file name>", a blank line, and the file's
# text without trailing newlines. Its size counts toward the batch.
function Get-Section($c) { "## Source: $(Split-Path -Leaf $c.Path)`n`n" + [IO.File]::ReadAllText($c.Path, $script:Utf8).TrimEnd("`n") }

if ($Mode -eq 'stage') {
    if (Test-Path -LiteralPath $dir) { Remove-Item -Recurse -Force -LiteralPath $dir }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'in'), (Join-Path $dir 'out') | Out-Null
}

# Batches: at most $limit code points of sections each; a same-mtime group is
# never split, and a group larger than the limit is a batch on its own.
$batches = [System.Collections.Generic.List[object]]::new()
$cur = [System.Collections.Generic.List[object]]::new(); $curChars = 0; $totalTokens = 0
function Close-Batch {
    if ($script:cur.Count -eq 0) { return }
    $k = $script:batches.Count
    $body = "Run date: $runDate`n`n$headText`n`n# New session files`n"
    foreach ($c in $script:cur) { $body += "`n" + (Get-Section $c) + "`n" }
    $script:totalTokens += [Math]::Floor((Get-CodePointLength $body) / 4)
    if ($Mode -eq 'stage') { Write-Utf8 (Join-Path $dir "in/batch-$k.md") $body }
    $script:batches.Add([ordered]@{
        cursorEpoch = $script:cur[$script:cur.Count - 1].Mtime
        files = [string[]]@($script:cur | ForEach-Object Rel)
        input = ".claude/session-lessons/staging/weekly-$Ext/in/batch-$k.md"
        pending = ".claude/session-lessons/staging/weekly-$Ext/out/batch-$k.md"
        exit = $null
    })
    $script:cur = [System.Collections.Generic.List[object]]::new(); $script:curChars = 0
}
$i = 0
while ($i -lt $files.Count) {
    $j = $i; $group = [System.Collections.Generic.List[object]]::new(); $gchars = 0
    while ($j -lt $files.Count -and $files[$j].Mtime -eq $files[$i].Mtime) {
        $group.Add($files[$j]); $gchars += Get-CodePointLength (Get-Section $files[$j]); $j++
    }
    if ($cur.Count -gt 0 -and $curChars + $gchars -gt $limit) { Close-Batch }
    $cur.AddRange($group); $curChars += $gchars
    $i = $j
}
Close-Batch

$since = if ($Cutoff -gt 0) { Get-LocalDate $Cutoff } else { 'the beginning' }
Write-Say "Weekly run ($Ext): $($files.Count) file(s) in $($batches.Count) batch(es), since $since."
Write-Say "About $totalTokens tokens (rough)."

if ($Mode -eq 'stage') {
    $manifest = [ordered]@{
        job = 'weekly'; extraction = $Ext; cursorFile = ".claude/session-lessons/state/weekly-$Ext.cursor"
        cutoffEpoch = $Cutoff; cursorEpoch = $newest; writeCursor = [bool]$WriteCursor; since = $since
        master = $master; mode = $wmode; runDate = $runDate; batches = @($batches)
    }
    Write-Utf8 (Join-Path $dir 'manifest.json') (($manifest | ConvertTo-Json -Depth 6) + "`n")
}
