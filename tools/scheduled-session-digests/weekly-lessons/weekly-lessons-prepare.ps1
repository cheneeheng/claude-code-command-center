# weekly-lessons-prepare.ps1
#
# Stages the weekly lessons harvest. Shared by both run mechanisms:
#   - cron : weekly-lessons-trigger.ps1 runs this, then runs `claude --print`.
#   - skill: the /session-digest-weekly-lessons skill runs this, then does the
#            harvest inline.
#
# What it does:
#   1. Reads the cursor file ($C4_CLAUDE_META_DIR\.claude\weekly-lessons-cursor,
#      Unix epoch mtime of the newest lessons file processed on the last
#      successful run) to determine the scan cutoff.
#   2. Scans lessons-learned\**\*.md (written by daily-lessons) for files newer
#      than the cutoff, skipping "no lessons" stub files.
#   3. Collects their content into input.md plus manifest.json in the staging
#      dir $C4_CLAUDE_META_DIR\.claude\scheduled-session-digests\weekly-lessons\
#      (gitignored, reset on every run).
#
# The consumer writes cursorEpoch to the cursor file only after a successful
# harvest, so a crash retries the same files on the next run.
#
# Manifest shape:
#   { "scheduler":   "weekly-lessons",
#     "cursor":      "<cursor file path>",
#     "cursorEpoch": <epoch to write to the cursor after a successful harvest>,
#     "files":       <number of collected source files>,
#     "input":       "<staged harvest input path>",
#     "master":      "<master lessons file path>" }
#
# Usage:
#   weekly-lessons-prepare.ps1 [-FullScan]

param(
    [switch]$FullScan
)

$ErrorActionPreference = "Stop"

$Tag     = "[weekly-lessons-prepare]"
$LogFile = $null

function Log {
    param([string]$Msg)
    $line = "[{0}] {1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $script:Tag, $Msg
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

$MetaDir = $env:C4_CLAUDE_META_DIR
if (-not $MetaDir) {
    Log "C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("{0}_weekly-lessons-prepare.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$LessonsBase = Join-Path $MetaDir "lessons-learned"
$MasterFile  = Join-Path $MetaDir "master-lessons\MASTER_LESSONS_LEARNED.md"
$CursorFile  = Join-Path $MetaDir ".claude\weekly-lessons-cursor"
$StagingDir  = Join-Path $MetaDir ".claude\scheduled-session-digests\weekly-lessons"
$InputFile   = Join-Path $StagingDir "input.md"
$Manifest    = Join-Path $StagingDir "manifest.json"
$Date        = Get-Date -Format "yyyy-MM-dd"
$UnixEpoch   = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)

# Truncate to whole seconds, matching bash `stat -c %Y`, so cursor comparisons
# behave identically on both platforms and fractional mtimes cannot make a file
# hover on the cutoff boundary.
function Get-FileEpoch {
    param([System.IO.FileSystemInfo]$File)
    [long][Math]::Floor(($File.LastWriteTimeUtc - $script:UnixEpoch).TotalSeconds)
}

# Keep the transient staging area out of git so a partial run is never committed.
$GitIgnore  = Join-Path $MetaDir ".gitignore"
$ignoreLine = ".claude/scheduled-session-digests/"
if (-not ((Test-Path $GitIgnore) -and (Select-String -Path $GitIgnore -SimpleMatch $ignoreLine -Quiet))) {
    Add-Content -Path $GitIgnore -Value $ignoreLine -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Reset the staging dir and write an empty manifest up front so the consumer
# always has something valid to read.
# ---------------------------------------------------------------------------
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

function Write-Manifest {
    param([long]$CursorEpoch, [int]$Files)
    $doc = [ordered]@{
        scheduler   = "weekly-lessons"
        cursor      = $CursorFile
        cursorEpoch = $CursorEpoch
        files       = $Files
        input       = $InputFile
        master      = $MasterFile
    }
    ConvertTo-Json $doc -Depth 3 | Set-Content $Manifest -Encoding UTF8
}

function Emit-Result {
    param([int]$Files)
    Write-Output "MANIFEST=$Manifest"
    Write-Output "JOBS=$Files"
}

Write-Manifest -CursorEpoch 0 -Files 0

if (-not (Test-Path $LessonsBase)) {
    Log "lessons-learned directory not found at $LessonsBase - has daily-lessons run yet?"
    Emit-Result -Files 0
    exit 0
}

# ---------------------------------------------------------------------------
# Determine the scan cutoff from the cursor file
# ---------------------------------------------------------------------------
if ($FullScan) {
    Log "Full scan requested - processing all lessons files."
    $CutoffEpoch = -1
    $cutoffLabel = "beginning of time (full scan)"
} elseif (Test-Path $CursorFile) {
    try {
        $CutoffEpoch = [long](Get-Content $CursorFile -Raw).Trim()
        $cutoffLabel = $UnixEpoch.AddSeconds($CutoffEpoch).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    } catch {
        Log "WARNING: cursor file unreadable - treating as first run."
        $CutoffEpoch = -1
        $cutoffLabel = "beginning of time (cursor reset)"
    }
} else {
    $CutoffEpoch = -1
    $cutoffLabel = "beginning of time (first run)"
}

# ---------------------------------------------------------------------------
# Find lessons files written after the cutoff; skip "no lessons" stubs
# ---------------------------------------------------------------------------
$LessonsFiles = @(Get-ChildItem -Path $LessonsBase -Filter "*.md" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { (Get-FileEpoch $_) -gt $CutoffEpoch } |
    Where-Object {
        $raw = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        $raw -and ($raw -notmatch '_No lessons extracted from this session\._')
    } |
    Sort-Object LastWriteTime)

if ($LessonsFiles.Count -eq 0) {
    Log "No new lessons files since $cutoffLabel - nothing to prepare."
    Emit-Result -Files 0
    exit 0
}

Log "Found $($LessonsFiles.Count) new lessons file(s) since $cutoffLabel."

# ---------------------------------------------------------------------------
# Build the harvest input file
# ---------------------------------------------------------------------------
$lines = [System.Text.StringBuilder]::new()
$null = $lines.AppendLine("# Lessons Harvest Input - $Date")
$null = $lines.AppendLine("")

foreach ($file in $LessonsFiles) {
    $rel      = $file.FullName.Substring($LessonsBase.Length).TrimStart('\', '/')
    $fileDate = $file.LastWriteTime.ToString("yyyy-MM-dd")
    $content  = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue

    $null = $lines.AppendLine("## Source: $rel")
    $null = $lines.AppendLine("Date: $fileDate")
    $null = $lines.AppendLine("")
    $null = $lines.Append($content.TrimEnd())
    $null = $lines.AppendLine("")
    $null = $lines.AppendLine("")
    $null = $lines.AppendLine("---")
    $null = $lines.AppendLine("")
}

Set-Content $InputFile $lines.ToString() -Encoding UTF8

# The consumer writes this to the cursor file after a successful harvest.
$CursorEpoch = Get-FileEpoch $LessonsFiles[-1]

Write-Manifest -CursorEpoch $CursorEpoch -Files $LessonsFiles.Count

Log "Collected $($LessonsFiles.Count) file(s) -> $InputFile"
Emit-Result -Files $LessonsFiles.Count
exit 0
