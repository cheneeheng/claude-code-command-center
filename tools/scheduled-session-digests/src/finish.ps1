#Requires -Version 7.4
# finish.ps1: single owner of splitting answers, validation, moving outputs
# into place, attempt counting, advancing the cursor, the last-run summary,
# git-sync, and staging cleanup. Called by run.ps1 after the claude calls.
#
# Cross-reference: src/finish.sh is the Bash twin.

param(
    [Parameter(Mandatory)][long]$Started,
    [ValidateSet('manual', 'scheduled')][string]$Trigger = 'manual',
    [string]$ErrorText = '',
    [string]$Log
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$dir = Join-Path $SlStaging 'daily'
$manifest = Get-Content -Raw (Join-Path $dir 'manifest.json') | ConvertFrom-Json -AsHashtable
$attemptsFile = Join-Path $SlState 'attempts.json'
$givenUpFile = Join-Path $SlState 'given-up.txt'
$max = [int]$SlConfig.maxAttempts
$attempts = if (Test-Path -LiteralPath $attemptsFile) { Get-Content -Raw $attemptsFile | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
$emDash = [char]0x2014

# A lessons part starts with "# Lessons — " and names the session. Any other
# extraction must be non-empty and contain the session UUID.
function Test-Part([string]$Ext, [string]$Uuid, [string]$Part) {
    if ($Ext -eq 'lessons') { return $Part.StartsWith("# Lessons $emDash ", 'Ordinal') -and $Part.Contains("**Session**: $Uuid") }
    $Part.Trim().Length -gt 0 -and $Part.Contains($Uuid)
}
function Test-None([string]$Ext, [string]$Part) { $Ext -eq 'lessons' -and $Part.Contains('_No lessons extracted from this session._') }

$processed = 0; $failed = 0; $given = 0; $oldestUndone = $null
$written = @{}; $none = @{}
foreach ($j in $manifest.jobs) {
    if ($j.exit -ne 0) {
        # Never called, or claude failed: nothing is moved or counted.
        if ($null -ne $j.exit) { $failed++ }
        if ($null -eq $oldestUndone) { $oldestUndone = [long]$j.mtime }
        continue
    }
    $processed++
    $answer = [IO.File]::ReadAllText((Join-Path $SlMeta $j.pending), $script:Utf8)
    $parts = Split-Answer $answer ([string[]]$j.needed)
    $doneAll = $true
    foreach ($e in $j.outputs.Keys) {
        $part = if ($parts.Contains($e)) { $parts[$e] } else { '' }
        if (Test-Part $e $j.uuid $part) {
            $dest = Join-Path $SlMeta $j.outputs[$e]
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Write-Utf8 $dest $part
            if (Test-None $e $part) { $none[$e] = 1 + [int]$none[$e] } else { $written[$e] = 1 + [int]$written[$e] }
        } else {
            $key = "${e}:$($j.uuid)"
            $n = 1 + [int]$attempts[$key]
            $attempts[$key] = $n
            if ($n -ge $max) {
                [IO.File]::AppendAllText($givenUpFile, "$key`n", $script:Utf8); $given++
                Write-Say "Gave up on $e for $($j.uuid.Substring(0,8)) after $n invalid answers."
            } else { $doneAll = $false }
        }
    }
    if (-not $doneAll) {
        $failed++
        if ($null -eq $oldestUndone) { $oldestUndone = [long]$j.mtime }
    }
}
Write-Utf8 $attemptsFile (($attempts | ConvertTo-Json -Depth 3) + "`n")

# Advance the cursor to the smaller of cursorEpoch and (oldest undone - 1).
if ($manifest.writeCursor) {
    $cur = [long]$manifest.cursorEpoch
    if ($null -ne $oldestUndone -and $oldestUndone - 1 -lt $cur) { $cur = $oldestUndone - 1 }
    Write-Utf8 (Join-Path $SlState 'daily.cursor') "$cur`n"
}

$deferred = [int]$manifest.deferred
Write-Say "Done: $processed processed, $failed failed (retried next run), $given given up, $deferred deferred."
$results = [ordered]@{}
foreach ($p in $SlConfig.extractions.PSObject.Properties) {
    if (-not $p.Value.enabled) { continue }
    $w = [int]$written[$p.Name]; $n = [int]$none[$p.Name]
    Write-Say "  $($p.Name): $w written, $n with nothing found."
    $results[$p.Name] = [ordered]@{ written = $w; none = $n }
}
if ($ErrorText) { Write-Say "Error: $ErrorText" }

$sync = & (Join-Path $PSScriptRoot 'git-sync.ps1') -Job daily -Log $script:SlLog

$lastRun = [ordered]@{
    job = 'daily'; startedAt = $Started; finishedAt = (Get-NowEpoch); trigger = $Trigger
    processed = $processed; results = $results; failed = $failed; givenUp = $given
    deferred = $deferred; committed = $sync.Committed; pushed = $sync.Pushed
    error = if ($ErrorText) { $ErrorText } else { $null }
}
Write-Utf8 (Join-Path $SlState 'last-run-daily.json') (($lastRun | ConvertTo-Json -Depth 4) + "`n")

Remove-Item -Recurse -Force -LiteralPath $dir
if (-not (Get-ChildItem -LiteralPath $SlStaging -Force)) { Remove-Item -Force -LiteralPath $SlStaging }
