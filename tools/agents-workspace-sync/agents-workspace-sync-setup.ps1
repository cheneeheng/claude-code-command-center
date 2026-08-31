# agents-workspace-sync-setup.ps1 - install / uninstall the agents-workspace-sync task
#
# What install does:
#   1. Ensures $C4_CLAUDE_META_DIR exists and sets the env var if missing
#   2. Copies agents-workspace-sync.ps1 into <meta>\.claude\scripts\
#   3. Writes <meta>\.claude\scripts\agents-workspace-sync-config.json (repo list + time)
#   4. Registers the \ClaudeAutomation\agents-workspace-sync daily task
#
# Uninstall removes the task, the installed script, and (unless -KeepConfig) the config.
# The claude-meta repo, its logs, and every target repo are left untouched.
#
# Examples:
#   .\agents-workspace-sync-setup.ps1                        # interactive install
#   .\agents-workspace-sync-setup.ps1 -Action uninstall
#   .\agents-workspace-sync-setup.ps1 -NonInteractive -Repos "C:\p\a\.agents_workspace"

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Repo paths to sync. Each must be a git repo in its own right.
    [string[]]$Repos,

    [string]$ScheduleTime,
    [string]$MetaDir,
    [switch]$NonInteractive,
    [switch]$KeepConfig
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot

$TaskName   = "agents-workspace-sync"
$TaskFolder = "\ClaudeAutomation\"

$Step = 0
function Step($Msg) { $script:Step++; Write-Host "[$script:Step] $Msg" -ForegroundColor Yellow }

function Prompt-Input {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " [$Default]" } else { "" }
    $raw  = Read-Host "  $Label$hint"
    if (-not $raw -and $Default) { return $Default }
    return $raw
}

if (-not $MetaDir) {
    $MetaDir = if ($env:C4_CLAUDE_META_DIR) { $env:C4_CLAUDE_META_DIR }
               else { Join-Path $env:USERPROFILE "claude-meta" }
}
$ScriptsDir = Join-Path $MetaDir ".claude\scripts"
$ConfigFile = Join-Path $ScriptsDir "agents-workspace-sync-config.json"
$Installed  = Join-Path $ScriptsDir "agents-workspace-sync.ps1"

# ===========================================================================
# Uninstall
# ===========================================================================
if ($Action -eq 'uninstall') {
    Write-Host ""
    Write-Host "=== Agents Workspace Sync - Uninstall ===" -ForegroundColor Cyan

    Step "Removing scheduled task..."
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "      Removed $TaskFolder$TaskName" -ForegroundColor Green
    } else {
        Write-Host "      Not registered - skipping." -ForegroundColor Gray
    }

    Step "Removing installed files..."
    if (Test-Path $Installed) {
        Remove-Item $Installed -Force
        Write-Host "      Removed $Installed" -ForegroundColor Green
    }
    if (-not $KeepConfig -and (Test-Path $ConfigFile)) {
        Remove-Item $ConfigFile -Force
        Write-Host "      Removed $ConfigFile" -ForegroundColor Green
    } elseif ($KeepConfig) {
        Write-Host "      Kept $ConfigFile" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=== Uninstall complete ===" -ForegroundColor Cyan
    Write-Host "Logs under $MetaDir\logs\ and every target repo were left untouched."
    return
}

# ===========================================================================
# Install
# ===========================================================================
Write-Host ""
Write-Host "=== Agents Workspace Sync - Install ===" -ForegroundColor Cyan
Write-Host "Meta repo   : $MetaDir"
Write-Host "Scripts dir : $ScriptsDir"
Write-Host ""

# ---- Settings ---------------------------------------------------------------
# 04:00 by default: after the digests (02:00 / 03:00) so the two automations never
# contend, and this one is not delayed by a long digest run.
if (-not $ScheduleTime) {
    $ScheduleTime = if ($NonInteractive) { "04:00" } else { Prompt-Input "Run time (HH:MM, 24h)" "04:00" }
}

if (-not $Repos) {
    if ($NonInteractive) { throw "agents-workspace-sync needs -Repos when run with -NonInteractive." }
    # Pre-fill from an existing config so re-running install is not a re-entry chore.
    $existing = @()
    if (Test-Path $ConfigFile) {
        try { $existing = @((Get-Content $ConfigFile -Raw | ConvertFrom-Json).repos) } catch { $existing = @() }
    }
    if ($existing) {
        Write-Host ""
        Write-Host "  Currently configured:" -ForegroundColor Gray
        $existing | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        $keep = Prompt-Input "Keep these? (y/n)" "y"
        if ($keep -match '^[Yy]') { $Repos = $existing }
    }
    if (-not $Repos) {
        Write-Host ""
        Write-Host "  Enter each .agents_workspace repo path; blank line to finish." -ForegroundColor Gray
        Write-Host "  e.g. C:\Users\me\WorkLocal\00_Project\agent-skills\.agents_workspace" -ForegroundColor Gray
        $collected = @()
        while ($true) {
            $p = Read-Host "  Repo path"
            if (-not $p) { break }
            $collected += $p.Trim().TrimEnd('\', '/')
        }
        $Repos = $collected
    }
}

$Repos = @($Repos | Where-Object { $_ -and $_.Trim() })
if (-not $Repos) { throw "No repo paths given - nothing to install." }

# ---------------------------------------------------------------------------
Step "Validating repo paths..."

# Warn now rather than let the first unattended run be the discovery. Each path must
# be its own repo top level; a path inside an outer repo is rejected at run time too.
$bad = 0
foreach ($r in $Repos) {
    $p = $r.TrimEnd('\', '/')
    if (-not (Test-Path $p)) {
        Write-Host "      MISSING : $p" -ForegroundColor Red; $bad++; continue
    }
    # Same root test the worker uses: --show-prefix is empty only at a repo root.
    $prefix = git -C $p rev-parse --show-prefix 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      NOT A REPO : $p" -ForegroundColor Red; $bad++; continue
    }
    if ($prefix) {
        $top = git -C $p rev-parse --show-toplevel 2>$null
        Write-Host "      NESTED IN $top : $p" -ForegroundColor Red; $bad++; continue
    }
    $branch = git -C $p branch --show-current 2>$null
    Write-Host "      OK ($branch) : $p" -ForegroundColor Green
}
if ($bad -gt 0) {
    Write-Host "      $bad path(s) will be logged as errors and skipped at run time." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Step "Setting up claude-meta dir..."

New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
if (-not (Test-Path (Join-Path $MetaDir ".git"))) {
    Push-Location $MetaDir
    git init -q
    Pop-Location
    Write-Host "      Initialised git repo: $MetaDir" -ForegroundColor Green
} else {
    Write-Host "      $MetaDir already present." -ForegroundColor Gray
}

$existingVar = [System.Environment]::GetEnvironmentVariable("C4_CLAUDE_META_DIR", "User")
if ($existingVar -ne $MetaDir) {
    [System.Environment]::SetEnvironmentVariable("C4_CLAUDE_META_DIR", $MetaDir, "User")
    $env:C4_CLAUDE_META_DIR = $MetaDir
    Write-Host "      Set C4_CLAUDE_META_DIR = $MetaDir" -ForegroundColor Green
} else {
    Write-Host "      C4_CLAUDE_META_DIR already set." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Step "Installing files..."

Copy-Item (Join-Path $Here "agents-workspace-sync.ps1") -Destination $Installed -Force
Write-Host "      $Installed" -ForegroundColor Green

$VersionSrc = Join-Path $Here "VERSION"
if (Test-Path $VersionSrc) {
    Copy-Item $VersionSrc -Destination (Join-Path $ScriptsDir "agents-workspace-sync.VERSION") -Force
}

[pscustomobject]@{
    scheduleTime = $ScheduleTime
    repos        = $Repos
} | ConvertTo-Json -Depth 3 | Set-Content $ConfigFile -Encoding UTF8
Write-Host "      $ConfigFile ($($Repos.Count) repo(s))" -ForegroundColor Green

# ---------------------------------------------------------------------------
Step "Registering Task Scheduler task..."

$TaskTrigger  = New-ScheduledTaskTrigger -Daily -At $ScheduleTime
$TaskAction   = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$Installed`""
# 15 minutes is generous for N git pushes; a hung credential prompt dies rather than
# lingering until the next day's run.
$TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue) {
    Set-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder `
        -Trigger $TaskTrigger -Action $TaskAction -Settings $TaskSettings | Out-Null
    Write-Host "      Updated: $TaskFolder$TaskName ($ScheduleTime daily)" -ForegroundColor Green
} else {
    Register-ScheduledTask `
        -TaskName    $TaskName `
        -TaskPath    $TaskFolder `
        -Trigger     $TaskTrigger `
        -Action      $TaskAction `
        -Settings    $TaskSettings `
        -Description "Daily commit and push of .agents_workspace repos" `
        -RunLevel    Limited | Out-Null
    Write-Host "      Registered: $TaskFolder$TaskName ($ScheduleTime daily)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "Logs: $MetaDir\logs\<yyyy>\<MM>\<timestamp>_agents-workspace-sync.log"
Write-Host ""
Write-Host "--- Verify ---" -ForegroundColor Yellow
Write-Host "     & '$Installed' -DryRun     # show what each repo would do"
Write-Host "     & '$Installed'             # run now"
Write-Host "     Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskFolder'"
Write-Host ""
Write-Host "Edit the repo list any time: $ConfigFile"
