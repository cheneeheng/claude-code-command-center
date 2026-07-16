# daily-digest-prepare.ps1
#
# Stages new Claude Code chats for one daily digest scheduler. Shared by both
# schedulers and both run mechanisms:
#   - cron : daily-digest-trigger.ps1 runs this, then feeds each staged job to
#            `claude --print`.
#   - skill: the /session-digest-<scheduler> skill runs this, then fans the
#            staged jobs out to subagents.
#
# What it does:
#   1. Reads the cursor file ($C4_CLAUDE_META_DIR\.claude\<scheduler>-cursor,
#      Unix epoch mtime of the newest chat handled on the last successful run)
#      to determine the scan cutoff.
#   2. Scans ~\.claude\projects\**\*.jsonl (and ~\.claude_devcontainer) for chat
#      files with mtime > cutoff, skipping already-processed UUIDs and sessions
#      below the configured turn/length thresholds.
#   3. Writes one input file per staged chat plus manifest.json to the staging
#      dir $C4_CLAUDE_META_DIR\.claude\scheduled-session-digests\<scheduler>\
#      (gitignored, reset on every run).
#
# The consumer advances the cursor only over jobs whose output file exists, so
# a crash retries the unprocessed chats on the next run (see the trigger and
# SKILL.md for the exact rule).
#
# Manifest shape:
#   { "scheduler":   "<name>",
#     "cursor":      "<cursor file path>",
#     "cursorEpoch": <epoch to write to the cursor after a fully successful run>,
#     "jobs": [ { "uuid", "date", "title", "project", "mtime",
#                 "input": "<staged input path>", "output": "<final output path>" } ] }
#
# Usage:
#   daily-digest-prepare.ps1 -Scheduler daily-summary|daily-lessons [-FullScan]

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily-summary', 'daily-lessons')]
    [string]$Scheduler,

    [switch]$FullScan
)

$ErrorActionPreference = "Stop"

# Per-scheduler settings; everything else is identical between the two.
$Settings = @{
    'daily-summary' = @{ OutputBase = 'daily-summaries'; ConfigKey = 'dailySummary' }
    'daily-lessons' = @{ OutputBase = 'lessons-learned'; ConfigKey = 'dailyLessons' }
}[$Scheduler]

$Tag     = "[$Scheduler-prepare]"
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
$LogFile = Join-Path $LogDir ("{0}_{1}-prepare.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $Scheduler)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$MetaDirName = Split-Path $MetaDir -Leaf
$ProjectsDir             = Join-Path $env:USERPROFILE ".claude\projects"
$DevcontainerProjectsDir = Join-Path $env:USERPROFILE ".claude_devcontainer\projects"
$OutputBase = Join-Path $MetaDir $Settings.OutputBase
$StagingDir = Join-Path $MetaDir ".claude\scheduled-session-digests\$Scheduler"
$Manifest   = Join-Path $StagingDir "manifest.json"
$CursorFile = Join-Path $MetaDir ".claude\$Scheduler-cursor"
$UnixEpoch  = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)

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
# Thresholds from scheduler-config.json (written by install.ps1)
# ---------------------------------------------------------------------------
$MinUserTurns       = 2
$MinTranscriptChars = 500
$ConfigFile = Join-Path $PSScriptRoot "scheduler-config.json"
if (Test-Path $ConfigFile) {
    $cfg = (Get-Content $ConfigFile -Raw | ConvertFrom-Json).($Settings.ConfigKey)
    if ($cfg) {
        if ($null -ne $cfg.minUserTurns)       { $MinUserTurns       = $cfg.minUserTurns }
        if ($null -ne $cfg.minTranscriptChars) { $MinTranscriptChars = $cfg.minTranscriptChars }
    }
}

# ---------------------------------------------------------------------------
# Reset the staging dir and write an empty manifest up front so the consumer
# always has something valid to read.
# ---------------------------------------------------------------------------
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

function Write-Manifest {
    param([object[]]$Jobs, [long]$CursorEpoch)
    $doc = [ordered]@{
        scheduler   = $Scheduler
        cursor      = $CursorFile
        cursorEpoch = $CursorEpoch
        jobs        = @($Jobs)
    }
    ConvertTo-Json $doc -Depth 5 | Set-Content $Manifest -Encoding UTF8
}

Write-Manifest -Jobs @() -CursorEpoch 0

function Emit-Result {
    param([int]$JobCount)
    Write-Output "MANIFEST=$Manifest"
    Write-Output "JOBS=$JobCount"
}

# ---------------------------------------------------------------------------
# Determine the scan cutoff from the cursor file
# ---------------------------------------------------------------------------
# $CutoffEpoch (whole seconds) drives the file scan; $Cutoff (DateTime) drives
# the per-message timestamp filter inside each transcript.
if ($FullScan) {
    Log "Full scan requested - scanning again from the first chat history."
    $CutoffEpoch = -1
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (full scan)"
} elseif (Test-Path $CursorFile) {
    try {
        $CutoffEpoch = [long](Get-Content $CursorFile -Raw).Trim()
        $Cutoff      = $UnixEpoch.AddSeconds($CutoffEpoch).ToLocalTime()
        $cutoffLabel = $Cutoff.ToString("yyyy-MM-dd HH:mm")
    } catch {
        Log "WARNING: cursor file unreadable - treating as first run."
        $CutoffEpoch = -1
        $Cutoff      = [DateTime]::MinValue
        $cutoffLabel = "beginning of time (cursor reset)"
    }
} else {
    $CutoffEpoch = -1
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (first run)"
}

# ---------------------------------------------------------------------------
# Find chat JSONL files modified after the cutoff, sorted oldest-first.
# The meta repo's own chats are excluded.
# ---------------------------------------------------------------------------
$ScanDirs = @()
if (Test-Path $ProjectsDir)             { $ScanDirs += $ProjectsDir }
if (Test-Path $DevcontainerProjectsDir) { $ScanDirs += $DevcontainerProjectsDir }

if ($ScanDirs.Count -eq 0) {
    Log "No projects directory found (checked $ProjectsDir and $DevcontainerProjectsDir) - nothing to prepare."
    Emit-Result -JobCount 0
    exit 0
}

$RecentFiles = @($ScanDirs |
    ForEach-Object {
        Get-ChildItem -Path $_ -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*$MetaDirName*" } |
            ForEach-Object {
                Get-ChildItem -Path $_.FullName -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { (Get-FileEpoch $_) -gt $CutoffEpoch }
            }
    } |
    Sort-Object LastWriteTime)

if ($RecentFiles.Count -eq 0) {
    Log "No chat histories updated since $cutoffLabel - nothing to prepare."
    Emit-Result -JobCount 0
    exit 0
}

Log "Found $($RecentFiles.Count) chat(s) modified since $cutoffLabel."

# Every recent file ends this run either staged or deliberately skipped, so a
# fully successful run may advance the cursor to the newest recent file's mtime.
$CursorEpoch = Get-FileEpoch $RecentFiles[-1]

# ---------------------------------------------------------------------------
# Stage one input file per chat
# ---------------------------------------------------------------------------
$jobs = [System.Collections.Generic.List[object]]::new()

foreach ($file in $RecentFiles) {
    $uuid      = $file.BaseName
    $chatDate  = $file.LastWriteTime.ToString("yyyy-MM-dd")
    $year      = $file.LastWriteTime.ToString("yyyy")
    $month     = $file.LastWriteTime.ToString("MM")
    $OutputDir = Join-Path $OutputBase "$year\$month"

    # Skip check: search the entire output tree so existing files are found
    # regardless of which year/month folder they landed in.
    if (Get-ChildItem -Path $OutputBase -Filter "*$uuid*" -Recurse -ErrorAction SilentlyContinue) {
        Log "Already processed: $uuid - skipping."
        continue
    }

    Log "Staging: $uuid ($chatDate)..."

    # ---- Extract metadata and transcript from the JSONL ----
    # Metadata (title, cwd) is read from the whole file; conversation entries at
    # or before the cutoff are dropped so only the new portion of a long-running
    # session is digested.
    $title         = $null
    $cwd           = $null
    $userTurnCount = 0
    $transcript    = [System.Text.StringBuilder]::new()

    Get-Content $file.FullName | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json -ErrorAction Stop

            if ($obj.type -eq 'custom-title' -and -not $title) { $title = $obj.customTitle }
            if ($obj.cwd -and -not $cwd)                        { $cwd   = $obj.cwd }

            if ($Cutoff -ne [DateTime]::MinValue -and $obj.timestamp) {
                if ([DateTime]$obj.timestamp -le $Cutoff) { return }
            }

            if ($obj.type -eq 'user' -and $obj.message.content) {
                # content is a plain string or an array of content blocks
                $userText = if ($obj.message.content -is [string]) {
                    $obj.message.content.Trim()
                } else {
                    (@($obj.message.content) |
                        Where-Object { $_.type -eq 'text' -and $_.text } |
                        ForEach-Object { $_.text }) -join "`n"
                }
                if ($userText) {
                    $userTurnCount++
                    $null = $transcript.AppendLine("[USER]")
                    $null = $transcript.AppendLine($userText)
                    $null = $transcript.AppendLine("")
                }
            }
            elseif ($obj.type -eq 'assistant' -and $obj.message.content) {
                $textBlocks = @($obj.message.content) | Where-Object { $_.type -eq 'text' -and $_.text }
                foreach ($block in $textBlocks) {
                    $text = $block.text.Trim()
                    if ($text.Length -gt 10000) { $text = $text.Substring(0, 10000) + "`n[...truncated]" }
                    $null = $transcript.AppendLine("[ASSISTANT]")
                    $null = $transcript.AppendLine($text)
                    $null = $transcript.AppendLine("")
                }
            }
        } catch {}
    }

    if ($transcript.Length -eq 0) {
        Log "No new messages in $uuid after cutoff - skipping."
        continue
    }

    if ($userTurnCount -lt $MinUserTurns -or $transcript.Length -lt $MinTranscriptChars) {
        Log "Skipping $uuid - too short ($userTurnCount turn(s), $($transcript.Length) chars)."
        continue
    }

    $projectName = if ($cwd) { Split-Path $cwd -Leaf } else { "unknown" }
    if (-not $title) { $title = $uuid }

    # Output filename: <date>_<uuid>_<safe-title>.md, title omitted if none set.
    $outName = if ($title -ne $uuid) {
        $safeTitle = $title -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
        "${chatDate}_${uuid}_${safeTitle}.md"
    } else {
        "${chatDate}_${uuid}.md"
    }
    $outFile   = Join-Path $OutputDir $outName
    $inputFile = Join-Path $StagingDir "$uuid.md"

    $header = @"
# Session Transcript
UUID: $uuid
Date: $chatDate
Title: $title
Project: $projectName
CWD: $cwd
Output: $outFile

## Conversation

"@
    Set-Content $inputFile ($header + $transcript.ToString()) -Encoding UTF8

    $jobs.Add([ordered]@{
        uuid    = $uuid
        date    = $chatDate
        title   = $title
        project = $projectName
        mtime   = Get-FileEpoch $file
        input   = $inputFile
        output  = $outFile
    })
}

Write-Manifest -Jobs $jobs.ToArray() -CursorEpoch $CursorEpoch

Log "Staged $($jobs.Count) job(s) -> $Manifest"
Emit-Result -JobCount $jobs.Count
exit 0
