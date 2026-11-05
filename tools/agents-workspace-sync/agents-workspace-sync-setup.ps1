# agents-workspace-sync-setup.ps1 - install / uninstall the agents-workspace-sync task
#
# What install does:
#   1. Copies agents-workspace-sync.ps1 and VERSION into <InstallDir>
#      (default ~\.claude-command-center\agents-workspace-sync\)
#   2. Writes <InstallDir>\config.json (repo list + time)
#   3. Registers the \ClaudeAutomation\agents-workspace-sync\agents-workspace-sync daily task
#   4. Deletes the files an older version installed into <meta>\.claude\scripts\
#      (<meta> = $C4_CLAUDE_META_DIR, else ~\claude-meta)
#
# Uninstall removes the task, the installed script, and (unless -KeepConfig) the config.
# The logs under <InstallDir>\logs\ and every target repo are left untouched.
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
    [string]$InstallDir = (Join-Path $HOME '.claude-command-center\agents-workspace-sync'),
    [switch]$NonInteractive,
    [switch]$KeepConfig
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot

$TaskName   = "agents-workspace-sync"
# Task folder nests this tool's folder name under the shared \ClaudeAutomation\ root
# (\ClaudeAutomation\agents-workspace-sync\), matching file-sync and the digests.
$TaskFolder = "\ClaudeAutomation\$(Split-Path -Leaf $PSScriptRoot)\"

$Step = 0
function Step($Msg) { $script:Step++; Write-Host "[$script:Step] $Msg" -ForegroundColor Yellow }

function Prompt-Input {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " [$Default]" } else { "" }
    $raw  = Read-Host "  $Label$hint"
    if (-not $raw -and $Default) { return $Default }
    return $raw
}

$ConfigFile = Join-Path $InstallDir "config.json"
$Installed  = Join-Path $InstallDir "agents-workspace-sync.ps1"
$VersionDst = Join-Path $InstallDir "VERSION"

# Where versions up to 0.1.x installed, inside the claude-meta repo.
$OldMeta    = if ($env:C4_CLAUDE_META_DIR) { $env:C4_CLAUDE_META_DIR } else { Join-Path $HOME "claude-meta" }
$OldScripts = Join-Path $OldMeta ".claude\scripts"
$OldConfig  = Join-Path $OldScripts "agents-workspace-sync-config.json"

function Remove-OldInstall {
    $old = @("agents-workspace-sync.ps1", "agents-workspace-sync.VERSION", "agents-workspace-sync-config.json" |
        ForEach-Object { Join-Path $OldScripts $_ } | Where-Object { Test-Path $_ })
    if (-not $old) {
        Write-Host "      Nothing under $OldScripts." -ForegroundColor Gray
        return
    }
    $old | ForEach-Object { Remove-Item $_ -Force; Write-Host "      Removed old $_" -ForegroundColor Green }
    Write-Host "      These were tracked in $OldMeta, whose git-sync commits the deletions." -ForegroundColor Gray
}

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
    foreach ($f in $Installed, $VersionDst) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Host "      Removed $f" -ForegroundColor Green }
    }
    if (-not $KeepConfig -and (Test-Path $ConfigFile)) {
        Remove-Item $ConfigFile -Force
        Write-Host "      Removed $ConfigFile" -ForegroundColor Green
    } elseif ($KeepConfig) {
        Write-Host "      Kept $ConfigFile" -ForegroundColor Gray
    }

    Step "Removing an older install..."
    Remove-OldInstall

    Write-Host ""
    Write-Host "=== Uninstall complete ===" -ForegroundColor Cyan
    Write-Host "Logs under $InstallDir\logs\ and every target repo were left untouched."
    return
}

# ===========================================================================
# Install
# ===========================================================================
Write-Host ""
Write-Host "=== Agents Workspace Sync - Install ===" -ForegroundColor Cyan
Write-Host "Install dir : $InstallDir"
Write-Host ""

# ---- Settings ---------------------------------------------------------------
# 04:00 by default: after the digests (02:00 / 03:00) so the two automations never
# contend, and this one is not delayed by a long digest run.
if (-not $ScheduleTime) {
    $ScheduleTime = if ($NonInteractive) { "04:00" } else { Prompt-Input "Run time (HH:MM, 24h)" "04:00" }
}

if (-not $Repos) {
    if ($NonInteractive) { throw "agents-workspace-sync needs -Repos when run with -NonInteractive." }
    # Pre-fill from an existing config, or the one an older version left in claude-meta,
    # so re-running install is not a re-entry chore.
    $existing = @()
    $prev = if (Test-Path $ConfigFile) { $ConfigFile } elseif (Test-Path $OldConfig) { $OldConfig }
    if ($prev) {
        try { $existing = @((Get-Content $prev -Raw | ConvertFrom-Json).repos) } catch { $existing = @() }
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
Step "Installing files..."

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item (Join-Path $Here "agents-workspace-sync.ps1") -Destination $Installed -Force
Write-Host "      $Installed" -ForegroundColor Green

$VersionSrc = Join-Path $Here "VERSION"
if (Test-Path $VersionSrc) {
    Copy-Item $VersionSrc -Destination $VersionDst -Force
}

[pscustomobject]@{
    scheduleTime = $ScheduleTime
    repos        = $Repos
} | ConvertTo-Json -Depth 3 | Set-Content $ConfigFile -Encoding UTF8
Write-Host "      $ConfigFile ($($Repos.Count) repo(s))" -ForegroundColor Green

# ---------------------------------------------------------------------------
Step "Registering Task Scheduler task..."

$TaskTrigger  = New-ScheduledTaskTrigger -Daily -At $ScheduleTime
# conhost --headless gives powershell a console that is never shown, so no window flashes on each run.
$TaskAction   = New-ScheduledTaskAction `
    -Execute "conhost.exe" `
    -Argument "--headless powershell.exe -NonInteractive -ExecutionPolicy Bypass -File `"$Installed`""
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

# ---------------------------------------------------------------------------
# After the task points at the new worker, so a failed registration leaves the old one working.
Step "Removing an older install..."
Remove-OldInstall

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "Logs: $InstallDir\logs\<yyyy>\<MM>\<timestamp>_agents-workspace-sync.log"
Write-Host ""
Write-Host "--- Verify ---" -ForegroundColor Yellow
Write-Host "     & '$Installed' -DryRun     # show what each repo would do"
Write-Host "     & '$Installed'             # run now"
Write-Host "     Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskFolder'"
Write-Host ""
Write-Host "Edit the repo list any time: $ConfigFile"
