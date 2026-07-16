# install.ps1 - weekly-lessons scheduler
#
# Run once from this directory.
#
# What it does:
#   1. Initialises %USERPROFILE%\claude-meta (git repo) with required subdirs
#   2. Sets C4_CLAUDE_META_DIR as a permanent user environment variable
#   3. Writes claude-meta\.claude\settings.json (Claude tool permissions)
#   4. Copies the scripts (weekly-lessons-prepare/-trigger, git-sync), the
#      weekly-lessons.md prompt, and the skill into the meta repo
#   5. Registers the SessionDigest-WeeklyLessons Task Scheduler task (Sunday 02:00)

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

$MetaDir    = if ($env:C4_CLAUDE_META_DIR) { $env:C4_CLAUDE_META_DIR } else { Join-Path $env:USERPROFILE "claude-meta" }
$ScriptsDir = Join-Path $MetaDir ".claude\scripts"

Write-Host ""
Write-Host "=== Weekly Lessons Harvest - Install ===" -ForegroundColor Cyan
Write-Host "Meta repo   : $MetaDir"
Write-Host "Scripts dir : $ScriptsDir"
Write-Host "Mode        : $Mode"
Write-Host ""

# ---- Schedule settings -------------------------------------------------------
Write-Host "  Schedule settings (press Enter to keep defaults):"
$ScheduleTime      = "02:00"
$ScheduleDayOfWeek = "Sunday"
if ($WantCron) {
    $ScheduleTime      = Prompt-Input "  Run time (HH:MM, 24h)" "02:00"
    $ScheduleDayOfWeek = Prompt-Input "  Day of week (Sunday/Monday/...)" "Sunday"
}
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Init claude-meta repo
# ---------------------------------------------------------------------------
Step "Setting up claude-meta repo..."

foreach ($dir in @("daily-summaries", "lessons-learned", "master-lessons")) {
    New-Item -ItemType Directory -Force -Path "$MetaDir\$dir" | Out-Null
}

if (-not (Test-Path (Join-Path $MetaDir ".git"))) {
    Push-Location $MetaDir
    git init -q
    foreach ($dir in @("daily-summaries", "lessons-learned", "master-lessons")) {
        New-Item -ItemType File -Force -Path "$MetaDir\$dir\.gitkeep" | Out-Null
        git add "$dir\.gitkeep"
    }
    git commit -q -m "init"
    Pop-Location
    Write-Host "      Created and initialised: $MetaDir" -ForegroundColor Green
} else {
    foreach ($dir in @("daily-summaries", "lessons-learned", "master-lessons")) {
        $keep = "$MetaDir\$dir\.gitkeep"
        if (-not (Test-Path $keep)) { New-Item -ItemType File -Force -Path $keep | Out-Null }
    }
    Write-Host "      Already exists - ensured subdirs present." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 2. Set C4_CLAUDE_META_DIR env var
# ---------------------------------------------------------------------------
Step "Setting C4_CLAUDE_META_DIR environment variable..."

$existing = [System.Environment]::GetEnvironmentVariable("C4_CLAUDE_META_DIR", "User")
if ($existing -ne $MetaDir) {
    [System.Environment]::SetEnvironmentVariable("C4_CLAUDE_META_DIR", $MetaDir, "User")
    $env:C4_CLAUDE_META_DIR = $MetaDir
    Write-Host "      Set C4_CLAUDE_META_DIR = $MetaDir" -ForegroundColor Green
} else {
    Write-Host "      Already set - skipping." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 3. Write claude-meta permissions
# ---------------------------------------------------------------------------
Step "Writing claude-meta settings..."

$MetaClaudeDir = Join-Path $MetaDir ".claude"
New-Item -ItemType Directory -Force -Path $MetaClaudeDir | Out-Null
$MetaSettings  = Join-Path $MetaClaudeDir "settings.json"

if (-not (Test-Path $MetaSettings)) {
    @'
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(mkdir:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(date:*)",
      "Bash(echo:*)",
      "Bash(powershell:*)",
      "Bash(pwsh:*)"
    ],
    "deny": []
  }
}
'@ | Set-Content $MetaSettings -Encoding UTF8
    Write-Host "      Created: $MetaSettings" -ForegroundColor Green
} else {
    Write-Host "      Already exists - skipping." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 4. Install command and trigger script
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

# The prepare script stages the work for both mechanisms (the trigger runs it).
Copy-Item "$Here\weekly-lessons-prepare.ps1" -Destination "$ScriptsDir\weekly-lessons-prepare.ps1" -Force
Write-Host "      $ScriptsDir\weekly-lessons-prepare.ps1" -ForegroundColor Green

# ---- Cron mechanism: trigger + prompt file ----
if ($WantCron) {
    Copy-Item "$Here\weekly-lessons.md"          -Destination "$ScriptsDir\weekly-lessons.md"          -Force
    Copy-Item "$Here\weekly-lessons-trigger.ps1" -Destination "$ScriptsDir\weekly-lessons-trigger.ps1" -Force
    Write-Host "      $ScriptsDir\weekly-lessons.md" -ForegroundColor Green
    Write-Host "      $ScriptsDir\weekly-lessons-trigger.ps1" -ForegroundColor Green
}

# ---- Skill mechanism: interactive SKILL.md ----
if ($WantSkill) {
    $SkillSrc = Join-Path $Here "..\skills\session-digest-weekly-lessons\SKILL.md"
    $SkillDir = Join-Path $MetaDir ".claude\skills\session-digest-weekly-lessons"
    if (Test-Path $SkillSrc) {
        New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
        Copy-Item $SkillSrc -Destination "$SkillDir\SKILL.md" -Force
        Write-Host "      $SkillDir\SKILL.md" -ForegroundColor Green
    } else {
        Write-Host "      WARNING: skill not found at $SkillSrc - /session-digest-weekly-lessons will be unavailable." -ForegroundColor Red
    }
}

# ---- Write / update scheduler-config.json -----------------------------------
$ConfigFile = Join-Path $ScriptsDir "scheduler-config.json"
$cfg = if (Test-Path $ConfigFile) { Get-Content $ConfigFile -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
$cfg | Add-Member -MemberType NoteProperty -Name "weeklyLessons" -Value ([PSCustomObject]@{
    scheduleTime       = $ScheduleTime
    scheduleDayOfWeek  = $ScheduleDayOfWeek
}) -Force
$cfg | ConvertTo-Json -Depth 3 | Set-Content $ConfigFile -Encoding UTF8
Write-Host "      $ConfigFile" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 5. Register Task Scheduler task
# ---------------------------------------------------------------------------
$TaskName   = "SessionDigest-WeeklyLessons"
# Subfolder = this member's folder name (the parent of each digest's own folder), so every
# digest task nests under \ClaudeAutomation\<member>\ and stays self-identifying to the member.
$MemberName = Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)
$TaskFolder = "\ClaudeAutomation\$MemberName\"
$Script     = "$ScriptsDir\weekly-lessons-trigger.ps1"

if ($WantCron) {
    Step "Registering Task Scheduler task..."

    if (-not (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue)) {
        $trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $ScheduleDayOfWeek -At $ScheduleTime
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
            -Description "Claude Code weekly cross-project lessons harvest" `
            -RunLevel    Limited | Out-Null

        Write-Host "      Registered: $TaskFolder$TaskName ($ScheduleTime $ScheduleDayOfWeek)" -ForegroundColor Green
    } else {
        Write-Host "      $TaskFolder$TaskName already registered - skipping." -ForegroundColor Gray
    }
}

$LogFile = Join-Path $MetaDir "logs\weekly-lessons.log"

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output: $MetaDir\master-lessons\MASTER_LESSONS_LEARNED.md"
Write-Host "Requires daily-lessons to have run at least once to populate lessons-learned/."

if ($WantCron) {
    Write-Host ""
    Write-Host "The harvest runs every $ScheduleDayOfWeek at $ScheduleTime."
    Write-Host "Logs: $LogFile"
    Write-Host ""
    Write-Host "--- Verify the cron scheduler ---" -ForegroundColor Yellow
    Write-Host "     Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskFolder'"
    Write-Host "     Get-Content '$LogFile' -Wait"
    Write-Host "     & '$ScriptsDir\weekly-lessons-trigger.ps1'   # test now"
}

if ($WantSkill) {
    Write-Host ""
    Write-Host "--- Use the interactive skill ---" -ForegroundColor Yellow
    Write-Host "     From inside Claude Code (run in $MetaDir): /session-digest-weekly-lessons"
}

Write-Host ""
Write-Host "Open a new terminal for C4_CLAUDE_META_DIR to take effect."
