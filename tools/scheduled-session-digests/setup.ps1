# setup.ps1 - interactive installer and uninstaller for scheduled-session-digests
#
# Run from the repo root:
#   .\setup.ps1

param(
    # Skip the interactive menu and drive everything from parameters.
    [switch]$NonInteractive,

    # Only used with -NonInteractive (the menu picks install/uninstall otherwise).
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Non-interactive install target (defaults to %USERPROFILE%\claude-meta).
    [string]$MetaDir,

    # Non-interactive scheduler picks. Tokens: <ds|dl|wl>-<skill|cron|both>
    # (e.g. ds-skill, dl-cron, wl-both).
    [string[]]$Picks
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot

# ---- Helpers ----------------------------------------------------------------

function Prompt-Input {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " [$Default]" } else { "" }
    $raw  = Read-Host "  $Label$hint"
    if (-not $raw -and $Default) { return $Default }
    return $raw
}

function Prompt-Confirm {
    param([string]$Label, [bool]$Default = $true)
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $raw  = Read-Host "  $Label $hint"
    if (-not $raw) { return $Default }
    return $raw -match '^[Yy]'
}

# ---- Banner -----------------------------------------------------------------

if ($NonInteractive) {
    $mode = $Action
} else {
    Write-Host ""
    Write-Host "  scheduled-session-digests" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1]  Install"
    Write-Host "  [2]  Uninstall"
    Write-Host "  [Q]  Quit"
    Write-Host ""

    $choice = Read-Host "  Choice"
    Write-Host ""

    switch ($choice.Trim().ToUpper()) {
        "1" { $mode = "install"   }
        "2" { $mode = "uninstall" }
        "Q" { exit 0 }
        default {
            Write-Host "  Invalid choice." -ForegroundColor Red
            exit 1
        }
    }
}

# =============================================================================
# INSTALL
# =============================================================================
if ($mode -eq "install") {

    # ---- Claude meta directory ----------------------------------------------
    $defaultMeta = if ($env:C4_CLAUDE_META_DIR) { $env:C4_CLAUDE_META_DIR } `
                   else { Join-Path $env:USERPROFILE "claude-meta" }

    if (-not $NonInteractive) {
        $MetaDir = Prompt-Input "Claude meta directory" $defaultMeta
    } elseif (-not $MetaDir) {
        $MetaDir = $defaultMeta
    }

    # ---- Validate / initialise git repo -------------------------------------
    $gitMarker = Join-Path $MetaDir ".git"

    if (Test-Path $MetaDir) {
        if (-not (Test-Path $gitMarker)) {
            Write-Host "  '$MetaDir' exists but is not a git repo." -ForegroundColor Yellow
            if ($NonInteractive -or (Prompt-Confirm "  Initialise as git repo?")) {
                Push-Location $MetaDir
                git init -q
                Pop-Location
                Write-Host "  Initialised." -ForegroundColor Green
            } else {
                Write-Host "  Aborted - the directory must be a git repo to continue." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "  Git repo found: $MetaDir" -ForegroundColor Green
        }
    } else {
        Write-Host "  '$MetaDir' does not exist." -ForegroundColor Yellow
        if ($NonInteractive -or (Prompt-Confirm "  Create and initialise as git repo?")) {
            New-Item -ItemType Directory -Force -Path $MetaDir | Out-Null
            Push-Location $MetaDir
            git init -q
            Pop-Location
            Write-Host "  Created and initialised: $MetaDir" -ForegroundColor Green
        } else {
            Write-Host "  Aborted." -ForegroundColor Red
            exit 1
        }
    }

    # ---- Persist C4_CLAUDE_META_DIR --------------------------------------------
    $env:C4_CLAUDE_META_DIR = $MetaDir
    $existing = [System.Environment]::GetEnvironmentVariable("C4_CLAUDE_META_DIR", "User")
    if ($existing -ne $MetaDir) {
        [System.Environment]::SetEnvironmentVariable("C4_CLAUDE_META_DIR", $MetaDir, "User")
        Write-Host "  Set C4_CLAUDE_META_DIR = $MetaDir" -ForegroundColor Green
    }

    # skill+cron -> both; otherwise the single chosen mechanism, or $null.
    function Mode-Of([bool]$Skill, [bool]$Cron) {
        if ($Skill -and $Cron) { return "both" }
        elseif ($Skill)        { return "skill" }
        elseif ($Cron)         { return "cron" }
        else                   { return $null }
    }

    if ($NonInteractive) {
        # Tokens: <ds|dl|wl>-<skill|cron|both> (e.g. ds-skill, dl-cron, wl-both).
        function Token-Mode([string]$Prefix) {
            $skill = $false; $cron = $false
            foreach ($t in $Picks) {
                switch ("$t".Trim().ToLower()) {
                    "$Prefix-skill" { $skill = $true }
                    "$Prefix-cron"  { $cron  = $true }
                    "$Prefix-both"  { $skill = $true; $cron = $true }
                }
            }
            Mode-Of $skill $cron
        }
        $dsMode = Token-Mode 'ds'
        $dlMode = Token-Mode 'dl'
        $wlMode = Token-Mode 'wl'
    } else {
        # ---- Which schedulers and mechanisms? -------------------------------
        Write-Host ""
        Write-Host "  Which to install? (comma-separated, e.g. 1,2,3)"
        Write-Host ""
        Write-Host "  Skill-based (interactive, runs inside Claude Code, no claude -p):"
        Write-Host "    [1]  daily-summary   (skill)"
        Write-Host "    [2]  daily-lessons   (skill)"
        Write-Host "    [3]  weekly-lessons  (skill)"
        Write-Host "  Cron-based (Task Scheduler + claude -p):"
        Write-Host "    [4]  daily-summary   (cron)"
        Write-Host "    [5]  daily-lessons   (cron)"
        Write-Host "    [6]  weekly-lessons  (cron)"
        Write-Host "    [7]  All of the above"
        Write-Host ""

        $sel   = Prompt-Input "Choice" "1,2,3"
        $picks = $sel -split ',' | ForEach-Object { $_.Trim() }
        if ($picks -contains "7") { $picks = @("1", "2", "3", "4", "5", "6") }

        foreach ($p in $picks) {
            if ($p -and $p -notin @("1", "2", "3", "4", "5", "6")) {
                Write-Host "  Invalid choice: '$p'" -ForegroundColor Red
                exit 1
            }
        }

        $dsMode = Mode-Of ($picks -contains "1") ($picks -contains "4")
        $dlMode = Mode-Of ($picks -contains "2") ($picks -contains "5")
        $wlMode = Mode-Of ($picks -contains "3") ($picks -contains "6")
    }

    if (-not ($dsMode -or $dlMode -or $wlMode)) {
        Write-Host "  Nothing selected." -ForegroundColor Red
        exit 1
    }

    Write-Host ""

    # ---- Run installers -----------------------------------------------------
    if ($dsMode) {
        Write-Host "  ── daily-summary ($dsMode) ───────────────────────────" -ForegroundColor Cyan
        & "$Here\daily-summary\install.ps1" -Mode $dsMode
        Write-Host ""
    }

    if ($dlMode) {
        Write-Host "  ── daily-lessons ($dlMode) ───────────────────────────" -ForegroundColor Cyan
        & "$Here\daily-lessons\install.ps1" -Mode $dlMode
        Write-Host ""
    }

    if ($wlMode) {
        Write-Host "  ── weekly-lessons ($wlMode) ──────────────────────────" -ForegroundColor Cyan
        & "$Here\weekly-lessons\install.ps1" -Mode $wlMode
        Write-Host ""
    }

    Write-Host "  ── Done ───────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Open a new terminal for C4_CLAUDE_META_DIR to take effect."
    if ($wlMode) {
        Write-Host "  Edit '$MetaDir\.claude\scheduled-repos.json' to add your repos."
    }
    Write-Host ""
}

# =============================================================================
# UNINSTALL
# =============================================================================
if ($mode -eq "uninstall") {

    if (-not $MetaDir) { $MetaDir = $env:C4_CLAUDE_META_DIR }
    if (-not $MetaDir) {
        if ($NonInteractive) {
            $MetaDir = Join-Path $env:USERPROFILE "claude-meta"
        } else {
            $MetaDir = Prompt-Input "claude-meta directory" (Join-Path $env:USERPROFILE "claude-meta")
        }
    }
    $scripts = Join-Path $MetaDir ".claude\scripts"

    function Remove-FileIfPresent([string]$Path) {
        if (Test-Path $Path) {
            Remove-Item $Path -Force
            Write-Host "  Removed: $Path" -ForegroundColor Green
        } else {
            Write-Host "  Not found: $Path" -ForegroundColor Gray
        }
    }

    # ---- Cron-based mechanism (scheduled tasks + trigger + prompt files) -----
    if ($NonInteractive -or (Prompt-Confirm "Remove the cron-based schedulers (scheduled tasks + trigger scripts)?")) {
        foreach ($task in @("SessionDigest-DailySummary", "SessionDigest-DailyLessons", "SessionDigest-WeeklyLessons")) {
            if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $task -Confirm:$false
                Write-Host "  Removed task: $task" -ForegroundColor Green
            } else {
                Write-Host "  Not found:    $task" -ForegroundColor Gray
            }
        }
        foreach ($f in @(
            "daily-summary.md",  "daily-summary-trigger.ps1",
            "daily-lessons.md",  "daily-lessons-trigger.ps1",
            "weekly-lessons.md", "weekly-lessons-trigger.ps1")) {
            Remove-FileIfPresent (Join-Path $scripts $f)
        }
    }

    Write-Host ""

    # ---- Skill-based mechanism (prepare scripts + interactive skills) --------
    if ($NonInteractive -or (Prompt-Confirm "Remove the skill-based schedulers (prepare scripts + skills)?")) {
        foreach ($f in @(
            "daily-summary-prepare.ps1",
            "daily-lessons-prepare.ps1",
            "weekly-lessons-prepare.ps1")) {
            Remove-FileIfPresent (Join-Path $scripts $f)
        }

        foreach ($s in @("daily-summary", "daily-lessons", "weekly-lessons")) {
            $path = Join-Path $MetaDir ".claude\skills\session-digest-$s"
            if (Test-Path $path) {
                Remove-Item $path -Recurse -Force
                Write-Host "  Removed: $path" -ForegroundColor Green
            } else {
                Write-Host "  Not found: $path" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""

    # ---- Shared files (used by both; remove only for a full clean) -----------
    if ((-not $NonInteractive) -and (Prompt-Confirm "Remove shared files (git-sync.ps1, VERSION, scheduler-config.json)?" $false)) {
        foreach ($f in @("git-sync.ps1", "VERSION", "scheduler-config.json")) {
            Remove-FileIfPresent (Join-Path $scripts $f)
        }
    }

    Write-Host ""
    Write-Host "  Uninstall complete." -ForegroundColor Cyan
    Write-Host ""
}
