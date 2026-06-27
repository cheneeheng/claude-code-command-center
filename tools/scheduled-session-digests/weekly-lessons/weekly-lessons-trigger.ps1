# weekly-lessons-trigger.ps1
#
# Triggered by Windows Task Scheduler every Sunday at 02:00.
# Scans $C4_CLAUDE_META_DIR/lessons-learned/**/*.md for files written since the
# last harvest, skips stub files, and passes the collected content to Claude
# for analysis and master-file update.
#
# Time filtering: a cursor file ($C4_CLAUDE_META_DIR/.claude/weekly-lessons-cursor)
# records the mtime (Unix epoch) of the newest lessons file processed on the
# last successful run. Only files newer than the cursor are processed.
# The cursor is updated only after Claude exits successfully, so a crash causes
# the same files to be retried on the next run.
#
# Task Scheduler setup (done by install.ps1, or manually):
#   Trigger : Weekly, Sunday, 02:00
#   Action  : powershell.exe -NonInteractive -File "%USERPROFILE%\claude-meta\.claude\scripts\weekly-lessons-trigger.ps1"

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

$MetaDir = $env:C4_CLAUDE_META_DIR
if (-not $MetaDir) {
    Log "[weekly-lessons] C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $ScriptBaseName)

$LessonsBase = Join-Path $MetaDir "lessons-learned"
$CursorFile  = Join-Path $MetaDir ".claude\weekly-lessons-cursor"
$PromptFile  = Join-Path $PSScriptRoot "weekly-lessons.md"
$InputFile   = Join-Path $PSScriptRoot "weekly-lessons-input.md"
$GitSync     = Join-Path $PSScriptRoot "git-sync.ps1"
$Date        = Get-Date -Format "yyyy-MM-dd"
$UnixEpoch   = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)

# Guard: prompt file must be installed alongside this script
if (-not (Test-Path $PromptFile)) {
    Log "[weekly-lessons] Prompt file not found at $PromptFile - run install.ps1 first."
    exit 1
}
if (-not (Test-Path $GitSync)) {
    Log "[weekly-lessons] git-sync.ps1 not found at $GitSync - run install.ps1 first."
    exit 1
}

# Guard: lessons-learned directory must exist
if (-not (Test-Path $LessonsBase)) {
    Log "[weekly-lessons] lessons-learned directory not found at $LessonsBase - has daily-lessons run yet?"
    exit 0
}

# ---------------------------------------------------------------------------
# Determine cutoff from cursor file
# ---------------------------------------------------------------------------
if ($FullScan) {
    Log "[weekly-lessons] Full scan requested - processing all lessons files."
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (full scan)"
} elseif (Test-Path $CursorFile) {
    try {
        $epochSeconds = [long](Get-Content $CursorFile -Raw -ErrorAction SilentlyContinue).Trim()
        $Cutoff      = $UnixEpoch.AddSeconds($epochSeconds).ToLocalTime()
        $cutoffLabel = $Cutoff.ToString("yyyy-MM-dd HH:mm")
    } catch {
        Log "[weekly-lessons] WARNING: cursor file unreadable - treating as first run."
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
    Log "[weekly-lessons] No new lessons files since $cutoffLabel - skipping."
    exit 0
}

Log "[weekly-lessons] Found $($LessonsFiles.Count) new lessons file(s) since $cutoffLabel."

# ---------------------------------------------------------------------------
# Build harvest input file for Claude
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

Log "[weekly-lessons] Collected $($LessonsFiles.Count) file(s). Passing to Claude..."

# ---------------------------------------------------------------------------
# Run Claude for analysis and master-file update
# ---------------------------------------------------------------------------
$Prompt = Get-Content $PromptFile -Raw

try {
    Set-Location $MetaDir
    claude --print $Prompt

    # Update cursor to the newest processed file's mtime - only on success so a
    # crash causes the same files to be retried next run.
    $latestFile  = $LessonsFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $newEpoch    = [long]($latestFile.LastWriteTime.ToUniversalTime() - $UnixEpoch).TotalSeconds
    Set-Content $CursorFile $newEpoch -Encoding ASCII
    Log "[weekly-lessons] Cursor updated to $($latestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))."
} finally {
    # Always clean up the input file so it is never committed by git-sync.
    Remove-Item $InputFile -ErrorAction SilentlyContinue
}

& $GitSync -Label "weekly-lessons"

Log "[weekly-lessons] Done. Check $MetaDir\master-lessons\ for updates."
