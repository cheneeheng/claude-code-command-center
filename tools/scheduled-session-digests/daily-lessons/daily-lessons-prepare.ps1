# daily-lessons-prepare.ps1
#
# Interactive-session variant of daily-lessons-trigger.ps1. Does everything the
# trigger does EXCEPT calling `claude --print` and git-sync. Instead of invoking
# Claude in a loop, it stages one input file per chat plus a manifest.json, and
# the /daily-lessons skill (running inside an interactive Claude Code session)
# fans the extraction out to subagents and commits afterwards.
#
# Stages:
#   $C4_CLAUDE_META_DIR\.claude\scheduler-jobs\daily-lessons\<uuid>.md   (input)
#   $C4_CLAUDE_META_DIR\.claude\scheduler-jobs\daily-lessons\manifest.json
# Each manifest entry records the input path and the final output path the
# subagent must write to: lessons-learned\YYYY\MM\<date>_<uuid>[_<title>].md
#
# Usage (normally invoked by the /daily-lessons skill):
#   $env:C4_CLAUDE_META_DIR="C:\path\to\claude-meta"; .\daily-lessons-prepare.ps1 [-FullScan]

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
    Log "[daily-lessons-prepare] C4_CLAUDE_META_DIR is not set - aborting."
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
    if ($cfg.dailyLessons) {
        if ($null -ne $cfg.dailyLessons.minUserTurns)       { $MinUserTurns       = $cfg.dailyLessons.minUserTurns }
        if ($null -ne $cfg.dailyLessons.minTranscriptChars) { $MinTranscriptChars = $cfg.dailyLessons.minTranscriptChars }
    }
}

$ProjectsDir             = Join-Path $env:USERPROFILE ".claude\projects"
$DevcontainerProjectsDir = Join-Path $env:USERPROFILE ".claude_devcontainer\projects"
$LessonsBase             = Join-Path $MetaDir "lessons-learned"
$JobsDir                 = Join-Path $MetaDir ".claude\scheduler-jobs\daily-lessons"
$Manifest                = Join-Path $JobsDir "manifest.json"

# Keep the transient staging area out of git so a partial run is never committed.
$GitIgnore = Join-Path $MetaDir ".gitignore"
$ignoreLine = ".claude/scheduler-jobs/"
if (-not ((Test-Path $GitIgnore) -and (Select-String -Path $GitIgnore -SimpleMatch $ignoreLine -Quiet))) {
    Add-Content -Path $GitIgnore -Value $ignoreLine -Encoding UTF8
}

# Reset staging dir and write an empty manifest up front.
if (Test-Path $JobsDir) { Remove-Item $JobsDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $JobsDir | Out-Null
Set-Content $Manifest "[]" -Encoding UTF8

# Build list of existing project dirs to scan
$ScanDirs = @()
if (Test-Path $ProjectsDir)             { $ScanDirs += $ProjectsDir }
if (Test-Path $DevcontainerProjectsDir) { $ScanDirs += $DevcontainerProjectsDir }

if ($ScanDirs.Count -eq 0) {
    Log "[daily-lessons-prepare] No projects directory found (checked $ProjectsDir and $DevcontainerProjectsDir) - nothing to prepare."
    Write-Output "MANIFEST=$Manifest"
    Write-Output "JOBS=0"
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
    Log "[daily-lessons-prepare] Full scan requested - scanning again from the first chat history."
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
    Log "[daily-lessons-prepare] No chat histories updated since $cutoffLabel - nothing to prepare."
    Write-Output "MANIFEST=$Manifest"
    Write-Output "JOBS=0"
    exit 0
}

Log "[daily-lessons-prepare] Found $($RecentFiles.Count) chat(s) modified since $cutoffLabel."

$jobs = [System.Collections.Generic.List[object]]::new()

# ---------------------------------------------------------------------------
# Process each chat file
# ---------------------------------------------------------------------------
foreach ($file in $RecentFiles) {
    $uuid        = $file.BaseName
    $chatDate    = $file.LastWriteTime.ToString("yyyy-MM-dd")
    $year        = $file.LastWriteTime.ToString("yyyy")
    $month       = $file.LastWriteTime.ToString("MM")
    $LessonsDir  = Join-Path $LessonsBase "$year\$month"

    if (Get-ChildItem -Path $LessonsBase -Filter "*$uuid*" -Recurse -ErrorAction SilentlyContinue) {
        Log "[daily-lessons-prepare] Already processed: $uuid - skipping."
        continue
    }

    Log "[daily-lessons-prepare] Staging: $uuid ($chatDate)..."

    # ---- Extract metadata and transcript from JSONL ----
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

    if ($transcript.Length -eq 0) {
        Log "[daily-lessons-prepare] No new messages in $uuid after cutoff - skipping."
        continue
    }

    if ($userTurnCount -lt $MinUserTurns -or $transcript.Length -lt $MinTranscriptChars) {
        Log "[daily-lessons-prepare] Skipping $uuid - too short ($userTurnCount turn(s), $($transcript.Length) chars)."
        continue
    }

    $projectName = if ($cwd) { Split-Path $cwd -Leaf } else { "unknown" }
    if (-not $title) { $title = $uuid }

    $outName = if ($title -ne $uuid) {
        $safeTitle = $title -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
        "${chatDate}_${uuid}_${safeTitle}.md"
    } else {
        "${chatDate}_${uuid}.md"
    }
    $outFile   = Join-Path $LessonsDir $outName
    $inputFile = Join-Path $JobsDir "$uuid.md"

    # ---- Write per-chat input file for the subagent ----
    $header = @"
# Lessons Input
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
        input   = $inputFile
        output  = $outFile
    })
}

# ConvertTo-Json collapses a single-element list to an object; force an array
# (PowerShell 5 has no -AsArray).
if ($jobs.Count -eq 0) {
    $json = "[]"
} elseif ($jobs.Count -eq 1) {
    $json = "[" + (ConvertTo-Json $jobs[0] -Depth 5) + "]"
} else {
    $json = ConvertTo-Json $jobs -Depth 5
}
Set-Content $Manifest $json -Encoding UTF8

Log "[daily-lessons-prepare] Staged $($jobs.Count) job(s) -> $Manifest"
Write-Output "MANIFEST=$Manifest"
Write-Output "JOBS=$($jobs.Count)"
