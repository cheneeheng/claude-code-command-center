# install.ps1 - daily-summary scheduler
#
# Run once from this directory.
#
# What it does:
#   1. Initialises %USERPROFILE%\claude-meta (git repo) with required subdirs
#   2. Sets CLAUDE_META_DIR as a permanent user environment variable
#   3. Copies daily-summary.md, daily-summary-trigger.ps1, git-sync.ps1 → %USERPROFILE%\claude-meta\.claude\scripts\
#   4. Registers the ClaudeCode-DailySummary Task Scheduler task (02:00 daily)
#
# How it works:
#   At 02:00 the trigger scans ~/.claude/projects/**/*.jsonl for new chat files,
#   passes each transcript to Claude for summarisation, and commits the results.

param(
    # Mode selects which mechanism to install:
    #   skill - prepare script + interactive SKILL.md (no Task Scheduler, no claude -p)
    #   cron  - trigger script + scheduled task (claude -p based)
    #   both  - everything (default)
    [ValidateSet('skill', 'cron', 'both')]
    [string]$Mode = 'both'
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$WantCron  = $Mode -in @('cron', 'both')
$WantSkill = $Mode -in @('skill', 'both')
$Step = 0
function Step($Msg) { $script:Step++; Write-Host "[$script:Step] $Msg" -ForegroundColor Yellow }

function Prompt-Input {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " [$Default]" } else { "" }
    $raw  = Read-Host "  $Label$hint"
    if (-not $raw -and $Default) { return $Default }
    return $raw
}

$MetaDir    = if ($env:CLAUDE_META_DIR) { $env:CLAUDE_META_DIR } else { Join-Path $env:USERPROFILE "claude-meta" }
$ScriptsDir = Join-Path $MetaDir ".claude\scripts"

Write-Host ""
Write-Host "=== Daily Summary Scheduler - Install ===" -ForegroundColor Cyan
Write-Host "Meta repo   : $MetaDir"
Write-Host "Scripts dir : $ScriptsDir"
Write-Host "Mode        : $Mode"
Write-Host ""

# ---- Schedule settings -------------------------------------------------------
Write-Host "  Schedule settings (press Enter to keep defaults):"
$ScheduleTime = "02:00"
if ($WantCron) { $ScheduleTime = Prompt-Input "  Run time (HH:MM, 24h)" "02:00" }
$MinUserTurns       = [int](Prompt-Input "  Min user turns to process a session" "2")
$MinTranscriptChars = [int](Prompt-Input "  Min transcript length (chars) to process a session" "500")
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Init claude-meta repo
# ---------------------------------------------------------------------------
Step "Setting up claude-meta repo..."

foreach ($dir in @("daily-summaries", "lessons-learned")) {
    New-Item -ItemType Directory -Force -Path "$MetaDir\$dir" | Out-Null
}

if (-not (Test-Path (Join-Path $MetaDir ".git"))) {
    Push-Location $MetaDir
    git init -q
    foreach ($dir in @("daily-summaries", "lessons-learned")) {
        New-Item -ItemType File -Force -Path "$MetaDir\$dir\.gitkeep" | Out-Null
        git add "$dir\.gitkeep"
    }
    git commit -q -m "init"
    Pop-Location
    Write-Host "      Created and initialised: $MetaDir" -ForegroundColor Green
} else {
    foreach ($dir in @("daily-summaries", "lessons-learned")) {
        $keep = "$MetaDir\$dir\.gitkeep"
        if (-not (Test-Path $keep)) { New-Item -ItemType File -Force -Path $keep | Out-Null }
    }
    Write-Host "      Already exists - ensured subdirs present." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 2. Set CLAUDE_META_DIR env var
# ---------------------------------------------------------------------------
Step "Setting CLAUDE_META_DIR environment variable..."

$existing = [System.Environment]::GetEnvironmentVariable("CLAUDE_META_DIR", "User")
if ($existing -ne $MetaDir) {
    [System.Environment]::SetEnvironmentVariable("CLAUDE_META_DIR", $MetaDir, "User")
    $env:CLAUDE_META_DIR = $MetaDir
    Write-Host "      Set CLAUDE_META_DIR = $MetaDir" -ForegroundColor Green
} else {
    Write-Host "      Already set - skipping." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 3. Install trigger script and git-sync
# ---------------------------------------------------------------------------
Step "Installing files..."

New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

# git-sync and VERSION are shared by both mechanisms.
$GitSyncSrc = Join-Path $Here "..\git-sync\git-sync.ps1"
if (Test-Path $GitSyncSrc) {
    Copy-Item $GitSyncSrc -Destination "$ScriptsDir\git-sync.ps1" -Force
    Write-Host "      $ScriptsDir\git-sync.ps1" -ForegroundColor Green
} else {
    Write-Host "      WARNING: git-sync.ps1 not found - run git-sync\install.ps1 manually." -ForegroundColor Red
}

$VersionSrc = Join-Path $Here "..\VERSION"
if (Test-Path $VersionSrc) {
    Copy-Item $VersionSrc -Destination "$ScriptsDir\VERSION" -Force
    Write-Host "      $ScriptsDir\VERSION" -ForegroundColor Green
}

# ---- Cron mechanism: trigger + prompt file ----
if ($WantCron) {
    Copy-Item "$Here\daily-summary.md"          -Destination "$ScriptsDir\daily-summary.md"          -Force
    Copy-Item "$Here\daily-summary-trigger.ps1" -Destination "$ScriptsDir\daily-summary-trigger.ps1" -Force
    Write-Host "      $ScriptsDir\daily-summary.md" -ForegroundColor Green
    Write-Host "      $ScriptsDir\daily-summary-trigger.ps1" -ForegroundColor Green
}

# ---- Skill mechanism: prepare script + interactive SKILL.md ----
if ($WantSkill) {
    Copy-Item "$Here\daily-summary-prepare.ps1" -Destination "$ScriptsDir\daily-summary-prepare.ps1" -Force
    Write-Host "      $ScriptsDir\daily-summary-prepare.ps1" -ForegroundColor Green

    $SkillSrc = Join-Path $Here "..\skills\claude-code-scheduler-daily-summary\SKILL.md"
    $SkillDir = Join-Path $MetaDir ".claude\skills\claude-code-scheduler-daily-summary"
    if (Test-Path $SkillSrc) {
        New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
        Copy-Item $SkillSrc -Destination "$SkillDir\SKILL.md" -Force
        Write-Host "      $SkillDir\SKILL.md" -ForegroundColor Green
    } else {
        Write-Host "      WARNING: skill not found at $SkillSrc - /claude-code-scheduler-daily-summary will be unavailable." -ForegroundColor Red
    }
}

# ---- Write / update scheduler-config.json -----------------------------------
$ConfigFile = Join-Path $ScriptsDir "scheduler-config.json"
$cfg = if (Test-Path $ConfigFile) { Get-Content $ConfigFile -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
$cfg | Add-Member -MemberType NoteProperty -Name "dailySummary" -Value ([PSCustomObject]@{
    scheduleTime        = $ScheduleTime
    minUserTurns        = $MinUserTurns
    minTranscriptChars  = $MinTranscriptChars
}) -Force
$cfg | ConvertTo-Json -Depth 3 | Set-Content $ConfigFile -Encoding UTF8
Write-Host "      $ConfigFile" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Register Task Scheduler task
# ---------------------------------------------------------------------------
$TaskName   = "ClaudeCode-DailySummary"
$TaskFolder = "\ClaudeCodeScheduler\"
$Script     = "$ScriptsDir\daily-summary-trigger.ps1"

if ($WantCron) {
    Step "Registering Task Scheduler task..."

    if (-not (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue)) {
        $trigger  = New-ScheduledTaskTrigger -Daily -At $ScheduleTime
        $action   = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NonInteractive -File `"$Script`""
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

        Register-ScheduledTask `
            -TaskName    $TaskName `
            -TaskPath    $TaskFolder `
            -Trigger     $trigger `
            -Action      $action `
            -Settings    $settings `
            -Description "Nightly git commit of Claude Code session summaries" `
            -RunLevel    Limited | Out-Null

        Write-Host "      Registered: $TaskFolder$TaskName ($ScheduleTime daily)" -ForegroundColor Green
    } else {
        Write-Host "      $TaskFolder$TaskName already registered - skipping." -ForegroundColor Gray
    }
}

$LogFile = Join-Path $MetaDir "logs\daily-summary.log"

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Open a new terminal for CLAUDE_META_DIR to take effect."

if ($WantCron) {
    Write-Host "Logs: $LogFile"
    Write-Host ""
    Write-Host "--- Verify the cron scheduler ---" -ForegroundColor Yellow
    Write-Host "     Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskFolder'"
    Write-Host "     Get-Content '$LogFile' -Wait"
    Write-Host "     & '$ScriptsDir\daily-summary-trigger.ps1'   # test now"
}

if ($WantSkill) {
    Write-Host ""
    Write-Host "--- Use the interactive skill ---" -ForegroundColor Yellow
    Write-Host "     From inside Claude Code (run in $MetaDir): /claude-code-scheduler-daily-summary"
}
