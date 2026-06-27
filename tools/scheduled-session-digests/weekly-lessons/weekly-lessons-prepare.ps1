# weekly-lessons-prepare.ps1
#
# Interactive-session variant of weekly-lessons-trigger.ps1. Does everything the
# trigger does EXCEPT calling `claude --print`, updating the cursor, and git-sync.
# It scans lessons-learned for files written since the last harvest, skips stubs,
# and writes the collected content to an input file. The /weekly-lessons skill
# (running inside an interactive Claude Code session) then reads that input plus
# the master file, updates the master, advances the cursor, and commits.
#
# Output (printed for the skill to consume):
#   INPUT=<harvest input file>
#   FILES=<number of source lessons files>
#   LATEST_EPOCH=<mtime of newest source file; write to CURSOR after success>
#   CURSOR=<cursor file path>
#   MASTER=<master lessons file path>
#
# Usage (normally invoked by the /weekly-lessons skill):
#   $env:CLAUDE_META_DIR="C:\path\to\claude-meta"; .\weekly-lessons-prepare.ps1 [-FullScan]

param(
    [switch]$FullScan
)

$ErrorActionPreference = "Stop"

$LogFile = $null

function Log {
    param([string]$Msg)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

$MetaDir = $env:CLAUDE_META_DIR
if (-not $MetaDir) {
    Log "[weekly-lessons-prepare] CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $ScriptBaseName)

$LessonsBase = Join-Path $MetaDir "lessons-learned"
$CursorFile  = Join-Path $MetaDir ".claude\weekly-lessons-cursor"
$MasterFile  = Join-Path $MetaDir "master-lessons\MASTER_LESSONS_LEARNED.md"
$JobsDir     = Join-Path $MetaDir ".claude\scheduler-jobs\weekly-lessons"
$InputFile   = Join-Path $JobsDir "input.md"
$Date        = Get-Date -Format "yyyy-MM-dd"
$UnixEpoch   = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)

# Keep the transient staging area out of git so it is never committed.
$GitIgnore = Join-Path $MetaDir ".gitignore"
$ignoreLine = ".claude/scheduler-jobs/"
if (-not ((Test-Path $GitIgnore) -and (Select-String -Path $GitIgnore -SimpleMatch $ignoreLine -Quiet))) {
    Add-Content -Path $GitIgnore -Value $ignoreLine -Encoding UTF8
}

if (Test-Path $JobsDir) { Remove-Item $JobsDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $JobsDir | Out-Null

# Guard: lessons-learned directory must exist
if (-not (Test-Path $LessonsBase)) {
    Log "[weekly-lessons-prepare] lessons-learned directory not found at $LessonsBase - has daily-lessons run yet?"
    Write-Output "FILES=0"
    exit 0
}

# ---------------------------------------------------------------------------
# Determine cutoff from cursor file
# ---------------------------------------------------------------------------
if ($FullScan) {
    Log "[weekly-lessons-prepare] Full scan requested - processing all lessons files."
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (full scan)"
} elseif (Test-Path $CursorFile) {
    try {
        $epochSeconds = [long](Get-Content $CursorFile -Raw -ErrorAction SilentlyContinue).Trim()
        $Cutoff      = $UnixEpoch.AddSeconds($epochSeconds).ToLocalTime()
        $cutoffLabel = $Cutoff.ToString("yyyy-MM-dd HH:mm")
    } catch {
        Log "[weekly-lessons-prepare] WARNING: cursor file unreadable - treating as first run."
        $Cutoff      = [DateTime]::MinValue
        $cutoffLabel = "beginning of time (cursor reset)"
    }
} else {
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (first run)"
}

# ---------------------------------------------------------------------------
# Find lessons files written after the cutoff; skip stubs
# ---------------------------------------------------------------------------
$LessonsFiles = Get-ChildItem -Path $LessonsBase -Filter "*.md" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $Cutoff } |
    Where-Object {
        $raw = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        $raw -and ($raw -notmatch '_No lessons extracted from this session\._')
    } |
    Sort-Object LastWriteTime

if ($LessonsFiles.Count -eq 0) {
    Log "[weekly-lessons-prepare] No new lessons files since $cutoffLabel - nothing to prepare."
    Write-Output "FILES=0"
    exit 0
}

Log "[weekly-lessons-prepare] Found $($LessonsFiles.Count) new lessons file(s) since $cutoffLabel."

# ---------------------------------------------------------------------------
# Build harvest input file
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

# Newest processed file's mtime - the skill writes this to the cursor on success.
$latestFile   = $LessonsFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$LatestEpoch  = [long]($latestFile.LastWriteTime.ToUniversalTime() - $UnixEpoch).TotalSeconds

Log "[weekly-lessons-prepare] Collected $($LessonsFiles.Count) file(s) -> $InputFile"
Write-Output "INPUT=$InputFile"
Write-Output "FILES=$($LessonsFiles.Count)"
Write-Output "LATEST_EPOCH=$LatestEpoch"
Write-Output "CURSOR=$CursorFile"
Write-Output "MASTER=$MasterFile"
