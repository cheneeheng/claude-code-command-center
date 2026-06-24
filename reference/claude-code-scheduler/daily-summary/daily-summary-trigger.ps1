# daily-summary-trigger.ps1
#
# Triggered by Windows Task Scheduler at 02:00 daily.
# Scans ~/.claude/projects/**/*.jsonl for files modified since the last run,
# extracts each conversation transcript, and passes it to Claude for summarisation.
# Each chat gets its own summary file: daily-summaries/YYYY/MM/<date>_<uuid>[_<title>].md
# Short transcripts are skipped based on thresholds in scheduler-config.json (default: < 2 turns or < 500 chars).
# After all chats are processed a single git-sync commit is made.
#
# Task Scheduler setup (done by install.ps1, or manually):
#   Trigger : Daily, 02:00
#   Action  : powershell.exe -NonInteractive -File "%USERPROFILE%\claude-meta\.claude\scripts\daily-summary-trigger.ps1"

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
    Log "[daily-summary] CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $ScriptBaseName)

$MetaDirName = Split-Path $MetaDir -Leaf

# ---------------------------------------------------------------------------
# Read configurable thresholds from scheduler-config.json (written by install.ps1)
# ---------------------------------------------------------------------------
$MinUserTurns       = 2
$MinTranscriptChars = 500
$ConfigFile = Join-Path $PSScriptRoot "scheduler-config.json"
if (Test-Path $ConfigFile) {
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    if ($cfg.dailySummary) {
        if ($null -ne $cfg.dailySummary.minUserTurns)       { $MinUserTurns       = $cfg.dailySummary.minUserTurns }
        if ($null -ne $cfg.dailySummary.minTranscriptChars) { $MinTranscriptChars = $cfg.dailySummary.minTranscriptChars }
    }
}

$ProjectsDir             = Join-Path $env:USERPROFILE ".claude\projects"
$DevcontainerProjectsDir = Join-Path $env:USERPROFILE ".claude_devcontainer\projects"
$SummariesBase = Join-Path $MetaDir "daily-summaries"
$PromptFile    = Join-Path $PSScriptRoot "daily-summary.md"
$InputFile     = Join-Path $PSScriptRoot "chat-input.md"
$GitSync       = Join-Path $PSScriptRoot "git-sync.ps1"
$LastSummary = Get-ChildItem -Path $SummariesBase -Filter "*.md" -Recurse `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($FullScan) {
    Log "[daily-summary] Full scan requested - scanning again from the first chat history."
    $Cutoff = [DateTime]::MinValue
}
elseif ($LastSummary) {
    $Cutoff = $LastSummary.LastWriteTime
} else {
    # First run - no prior summaries, process entire history
    $Cutoff = [DateTime]::MinValue
}

if (-not (Test-Path $PromptFile)) {
    Log "[daily-summary] Prompt file not found at $PromptFile - run install.ps1 first."
    exit 1
}
if (-not (Test-Path $GitSync)) {
    Log "[daily-summary] git-sync.ps1 not found at $GitSync - run install.ps1 first."
    exit 1
}
# Build list of existing project dirs to scan
$ScanDirs = @()
if (Test-Path $ProjectsDir)             { $ScanDirs += $ProjectsDir }
if (Test-Path $DevcontainerProjectsDir) { $ScanDirs += $DevcontainerProjectsDir }

if ($ScanDirs.Count -eq 0) {
    Log "[daily-summary] No projects directory found (checked $ProjectsDir and $DevcontainerProjectsDir) - skipping."
    exit 0
}

# ---------------------------------------------------------------------------
# Find JSONL files modified in the last 24 hours
# ---------------------------------------------------------------------------
$RecentFiles = $ScanDirs |
    ForEach-Object {
        Get-ChildItem -Path $_ -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*$MetaDirName*" } |
            ForEach-Object {
                Get-ChildItem -Path $_.FullName -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $Cutoff }
            }
    } |
    Sort-Object LastWriteTime

$cutoffLabel = if ($Cutoff -eq [DateTime]::MinValue) { "beginning of time (first run)" } `
               else { $Cutoff.ToString("yyyy-MM-dd HH:mm") }

if ($RecentFiles.Count -eq 0) {
    Log "[daily-summary] No chat histories updated since $cutoffLabel - skipping."
    exit 0
}

Log "[daily-summary] Found $($RecentFiles.Count) chat(s) modified since $cutoffLabel."
New-Item -ItemType Directory -Force -Path $SummariesBase | Out-Null

$Prompt    = Get-Content $PromptFile -Raw
$Processed = 0

# ---------------------------------------------------------------------------
# Process each chat file
# ---------------------------------------------------------------------------
foreach ($file in $RecentFiles) {
    $uuid         = $file.BaseName
    $chatDate     = $file.LastWriteTime.ToString("yyyy-MM-dd")
    $year         = $file.LastWriteTime.ToString("yyyy")
    $month        = $file.LastWriteTime.ToString("MM")
    $SummariesDir = Join-Path $SummariesBase "$year\$month"

    # Skip check: search entire base tree so existing summaries are always found
    # regardless of which year/month folder they landed in
    if (Get-ChildItem -Path $SummariesBase -Filter "*$uuid*" -Recurse -ErrorAction SilentlyContinue) {
        Log "[daily-summary] Already summarised: $uuid - skipping."
        continue
    }

    Log "[daily-summary] Processing: $uuid ($chatDate)..."

    # ---- Extract metadata and transcript from JSONL ----
    # Metadata (title, cwd) is read from the whole file - these entries appear early
    # and may be before the cutoff. Conversation entries are filtered to $Cutoff so
    # that only the new portion of a long-running session is summarised.
    $title         = $null
    $cwd           = $null
    $userTurnCount = 0
    $transcript    = [System.Text.StringBuilder]::new()

    Get-Content $file.FullName | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json -ErrorAction Stop

            # Always capture metadata regardless of timestamp
            if ($obj.type -eq 'custom-title' -and -not $title) { $title = $obj.customTitle }
            if ($obj.cwd -and -not $cwd)                        { $cwd   = $obj.cwd }

            # For conversation entries, skip anything at or before the cutoff
            if ($Cutoff -ne [DateTime]::MinValue -and $obj.timestamp) {
                if ([DateTime]$obj.timestamp -le $Cutoff) { return }
            }

            if ($obj.type -eq 'user' -and $obj.message.content) {
                $userTurnCount++
                $null = $transcript.AppendLine("[USER]")
                $null = $transcript.AppendLine($obj.message.content.ToString().Trim())
                $null = $transcript.AppendLine("")
            }
            elseif ($obj.type -eq 'assistant' -and $obj.message.content) {
                $textBlocks = @($obj.message.content) | Where-Object { $_.type -eq 'text' -and $_.text }
                foreach ($block in $textBlocks) {
                    $text = $block.text.Trim()
                    if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) + "`n[...truncated]" }
                    $null = $transcript.AppendLine("[ASSISTANT]")
                    $null = $transcript.AppendLine($text)
                    $null = $transcript.AppendLine("")
                }
            }
        } catch {}
    }

    # Skip if filtering left nothing to summarise
    if ($transcript.Length -eq 0) {
        Log "[daily-summary] No new messages in $uuid after cutoff - skipping."
        continue
    }

    # Skip transcripts that are too short to be worth summarising:
    #   - fewer than 2 user turns  (single-message exchanges, accidental opens)
    #   - total transcript under 500 chars  (~80 words)
    # Both thresholds must be passed; a single long message still fails the turn check.
    if ($userTurnCount -lt $MinUserTurns -or $transcript.Length -lt $MinTranscriptChars) {
        Log "[daily-summary] Skipping $uuid - too short ($userTurnCount turn(s), $($transcript.Length) chars)."
        continue
    }

    $projectName = if ($cwd) { Split-Path $cwd -Leaf } else { "unknown" }
    if (-not $title) { $title = $uuid }

    # Build output filename: <date>_<uuid>_<title>.md if custom title available,
    # otherwise <date>_<uuid>.md
    $outName = if ($title -ne $uuid) {
        $safeTitle = $title -replace '[\\/:*?"<>|]', '-' -replace '\s+', '_'
        "${chatDate}_${uuid}_${safeTitle}.md"
    } else {
        "${chatDate}_${uuid}.md"
    }
    New-Item -ItemType Directory -Force -Path $SummariesDir | Out-Null
    $outFile = Join-Path $SummariesDir $outName

    # ---- Write input file for Claude ----
    $header = @"
# Chat History Input
UUID: $uuid
Date: $chatDate
Title: $title
Project: $projectName
CWD: $cwd
Output: $outFile

## Conversation

"@
    Set-Content $InputFile ($header + $transcript.ToString()) -Encoding UTF8

    # ---- Invoke Claude ----
    Set-Location $MetaDir
    claude --model haiku --print $Prompt

    Remove-Item $InputFile -ErrorAction SilentlyContinue
    $Processed++
}

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if ($Processed -gt 0) {
    & $GitSync -Label "daily-summary"
    Log "[daily-summary] Done. Summarised $Processed chat(s)."
} else {
    Log "[daily-summary] All recent chats already summarised - nothing to commit."
}
