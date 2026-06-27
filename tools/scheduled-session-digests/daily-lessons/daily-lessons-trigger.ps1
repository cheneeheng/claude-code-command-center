# daily-lessons-trigger.ps1
#
# Triggered by Windows Task Scheduler at 03:00 daily (staggered from daily-summary
# at 02:00 to avoid concurrent git-sync conflicts on the same meta repo).
# Scans ~/.claude/projects/**/*.jsonl for files modified since the last run,
# extracts each conversation transcript, and passes it to Claude for lessons
# extraction via the ceh-lessons-learned skill.
# Each chat gets its own file: lessons-learned\YYYY\MM\<date>_<uuid>[_<title>].md
# Short transcripts are skipped based on thresholds in scheduler-config.json (default: < 2 turns or < 500 chars).
# Sessions that produce no lessons get a stub file so they are not reprocessed.
# After all chats are processed a single git-sync commit is made.
#
# Task Scheduler setup (done by install.ps1, or manually):
#   Trigger : Daily, 03:00
#   Action  : powershell.exe -NonInteractive -File "%USERPROFILE%\claude-meta\.claude\scripts\daily-lessons-trigger.ps1"

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
    Log "[daily-lessons] C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $ScriptBaseName)

$MetaDirName             = Split-Path $MetaDir -Leaf

# ---------------------------------------------------------------------------
# Read configurable thresholds from scheduler-config.json (written by install.ps1)
# ---------------------------------------------------------------------------
$MinUserTurns       = 2
$MinTranscriptChars = 500
$ConfigFile = Join-Path $PSScriptRoot "scheduler-config.json"
if (Test-Path $ConfigFile) {
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    if ($cfg.dailyLessons) {
        if ($null -ne $cfg.dailyLessons.minUserTurns)       { $MinUserTurns       = $cfg.dailyLessons.minUserTurns }
        if ($null -ne $cfg.dailyLessons.minTranscriptChars) { $MinTranscriptChars = $cfg.dailyLessons.minTranscriptChars }
    }
}

$ProjectsDir             = Join-Path $env:USERPROFILE ".claude\projects"
$DevcontainerProjectsDir = Join-Path $env:USERPROFILE ".claude_devcontainer\projects"
$LessonsBase             = Join-Path $MetaDir "lessons-learned"
$LessonsStaging          = Join-Path $MetaDir "docs\claude_logs\LESSONS_LEARNED.md"
$PromptFile              = Join-Path $PSScriptRoot "daily-lessons.md"
$InputFile               = Join-Path $PSScriptRoot "lessons-input.md"
$GitSync                 = Join-Path $PSScriptRoot "git-sync.ps1"

if (-not (Test-Path $PromptFile)) {
    Log "[daily-lessons] Prompt file not found at $PromptFile - run install.ps1 first."
    exit 1
}
if (-not (Test-Path $GitSync)) {
    Log "[daily-lessons] git-sync.ps1 not found at $GitSync - run install.ps1 first."
    exit 1
}

# Build list of existing project dirs to scan
$ScanDirs = @()
if (Test-Path $ProjectsDir)             { $ScanDirs += $ProjectsDir }
if (Test-Path $DevcontainerProjectsDir) { $ScanDirs += $DevcontainerProjectsDir }

if ($ScanDirs.Count -eq 0) {
    Log "[daily-lessons] No projects directory found (checked $ProjectsDir and $DevcontainerProjectsDir) - skipping."
    exit 0
}

# ---------------------------------------------------------------------------
# Determine cutoff: modification time of the most recently written lessons file
# ---------------------------------------------------------------------------
$LastFile = Get-ChildItem -Path $LessonsBase -Filter "*.md" -Recurse `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($FullScan) {
    Log "[daily-lessons] Full scan requested - scanning again from the first chat history."
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (full scan)"
} elseif ($LastFile) {
    $Cutoff      = $LastFile.LastWriteTime
    $cutoffLabel = $Cutoff.ToString("yyyy-MM-dd HH:mm")
} else {
    $Cutoff      = [DateTime]::MinValue
    $cutoffLabel = "beginning of time (first run)"
}

# ---------------------------------------------------------------------------
# Find JSONL files modified after the cutoff, sorted oldest-first
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

if ($RecentFiles.Count -eq 0) {
    Log "[daily-lessons] No chat histories updated since $cutoffLabel - skipping."
    exit 0
}

Log "[daily-lessons] Found $($RecentFiles.Count) chat(s) modified since $cutoffLabel."
New-Item -ItemType Directory -Force -Path $LessonsBase | Out-Null

$Prompt    = Get-Content $PromptFile -Raw
$Processed = 0

# ---------------------------------------------------------------------------
# Process each chat file
# ---------------------------------------------------------------------------
foreach ($file in $RecentFiles) {
    $uuid        = $file.BaseName
    $chatDate    = $file.LastWriteTime.ToString("yyyy-MM-dd")
    $year        = $file.LastWriteTime.ToString("yyyy")
    $month       = $file.LastWriteTime.ToString("MM")
    $LessonsDir  = Join-Path $LessonsBase "$year\$month"

    # Skip check: search entire base tree so existing files are always found
    # regardless of which year/month folder they landed in
    if (Get-ChildItem -Path $LessonsBase -Filter "*$uuid*" -Recurse -ErrorAction SilentlyContinue) {
        Log "[daily-lessons] Already processed: $uuid - skipping."
        continue
    }

    Log "[daily-lessons] Processing: $uuid ($chatDate)..."

    # ---- Extract metadata and transcript from JSONL ----
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
                # content may be a plain string or an array of content blocks
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
                    if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) + "`n[...truncated]" }
                    $null = $transcript.AppendLine("[ASSISTANT]")
                    $null = $transcript.AppendLine($text)
                    $null = $transcript.AppendLine("")
                }
            }
        } catch {}
    }

    # Skip if filtering left nothing to process
    if ($transcript.Length -eq 0) {
        Log "[daily-lessons] No new messages in $uuid after cutoff - skipping."
        continue
    }

    # Short-session filter (thresholds read from scheduler-config.json)
    if ($userTurnCount -lt $MinUserTurns -or $transcript.Length -lt $MinTranscriptChars) {
        Log "[daily-lessons] Skipping $uuid - too short ($userTurnCount turn(s), $($transcript.Length) chars)."
        continue
    }

    $projectName = if ($cwd) { Split-Path $cwd -Leaf } else { "unknown" }
    if (-not $title) { $title = $uuid }

    # Build output filename: <date>_<uuid>_<title>.md if custom title available,
    # otherwise <date>_<uuid>.md
    $outName = if ($title -ne $uuid) {
        $safeTitle = $title -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
        "${chatDate}_${uuid}_${safeTitle}.md"
    } else {
        "${chatDate}_${uuid}.md"
    }
    New-Item -ItemType Directory -Force -Path $LessonsDir | Out-Null
    $outFile = Join-Path $LessonsDir $outName

    # ---- Write input file for Claude ----
    $header = @"
# Lessons Input
UUID: $uuid
Date: $chatDate
Title: $title
Project: $projectName
CWD: $cwd

## Conversation

"@
    Set-Content $InputFile ($header + $transcript.ToString()) -Encoding UTF8

    # ---- Clear staging file so the skill writes a fresh one ----
    $stagingDir = Split-Path $LessonsStaging -Parent
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
    if (Test-Path $LessonsStaging) { Remove-Item $LessonsStaging -Force }

    # ---- Invoke Claude ----
    Set-Location $MetaDir
    claude --print "$Prompt"

    # ---- Move or stub the output ----
    if ((Test-Path $LessonsStaging) -and (Get-Item $LessonsStaging).Length -gt 0) {
        Move-Item $LessonsStaging -Destination $outFile -Force
        Log "[daily-lessons] Written: $outFile"
    } else {
        # Write a stub so the UUID is marked as processed and not retried.
        if (Test-Path $LessonsStaging) { Remove-Item $LessonsStaging -Force }
        $stub = @"
# Lessons - $chatDate
**Session**: $uuid
**Title**: $title
**Project**: $projectName

_No lessons extracted from this session._
"@
        Set-Content $outFile $stub -Encoding UTF8
        Log "[daily-lessons] No lessons produced for $uuid - stub written."
    }

    Remove-Item $InputFile -ErrorAction SilentlyContinue
    $Processed++
}

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if ($Processed -gt 0) {
    & $GitSync -Label "daily-lessons"
    Log "[daily-lessons] Done. Processed $Processed chat(s)."
} else {
    Log "[daily-lessons] All recent chats already processed - nothing to commit."
}
