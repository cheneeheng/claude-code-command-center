# Install / uninstall usage-insights from this checkout (Windows).
#
# install:
#   1. Builds the web frontend (bun) into src/usage_insights/static/.
#   2. Installs the `usage-insights` command with `uv tool install --editable`.
#   3. Registers \ClaudeAutomation\usage-insights\export, which runs
#      `usage-insights-bg.exe export` daily at 12:00 and at logon, with no console window.
# uninstall: removes the task and the command. The store (usage.db) is kept.
#
# Usage:
#   .\usage-insights-setup.ps1                     # install (default)
#   .\usage-insights-setup.ps1 -Action uninstall
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install'
)

$ErrorActionPreference = 'Stop'

$AppDir     = Split-Path $PSScriptRoot
$WebDir     = Join-Path $AppDir 'web'
# Task folder nests the app's folder name under the shared \ClaudeAutomation\ root.
$TaskFolder = "\ClaudeAutomation\$(Split-Path -Leaf $AppDir)\"
$TaskName   = 'export'
$StoreDir   = if ($env:C4_USAGE_INSIGHTS_HOME) { $env:C4_USAGE_INSIGHTS_HOME }
              else { Join-Path $env:USERPROFILE '.usage-insights' }
$StorePath  = Join-Path $StoreDir 'usage.db'

function Invoke-Native([string]$What, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE)" }
}

function Assert-OnPath([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' is not on PATH. $Hint"
    }
}

if ($Action -eq 'uninstall') {
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Removed task $TaskFolder$TaskName"
    } else {
        Write-Host "Task $TaskFolder$TaskName not found, skipped."
    }
    Assert-OnPath 'uv' 'Install it from https://docs.astral.sh/uv/'
    $tools = uv tool list
    if ($LASTEXITCODE -ne 0) { throw "uv tool list failed (exit $LASTEXITCODE)" }
    if ($tools | Select-String -Pattern '^usage-insights ' -Quiet) {
        Invoke-Native 'uv tool uninstall' { uv tool uninstall usage-insights }
    } else {
        Write-Host 'usage-insights command not installed, skipped.'
    }
    Write-Host "Kept the store: $StorePath"
    return
}

Assert-OnPath 'bun' 'Install it from https://bun.sh/'
Assert-OnPath 'uv' 'Install it from https://docs.astral.sh/uv/'

Write-Host '[1] Building the web frontend...'
Push-Location $WebDir
try {
    Invoke-Native 'bun install' { bun install --frozen-lockfile }
    Invoke-Native 'bun run build' { bun run build }
} finally {
    Pop-Location
}

Write-Host '[2] Installing the usage-insights command...'
# --reinstall makes a re-run pick up dependency changes in libs/.
Invoke-Native 'uv tool install' { uv tool install --editable $AppDir --reinstall }
$BinDir = (uv tool dir --bin)
if ($LASTEXITCODE -ne 0) { throw "uv tool dir --bin failed (exit $LASTEXITCODE)" }
$BgExe = Join-Path $BinDir 'usage-insights-bg.exe'
if (-not (Test-Path $BgExe)) { throw "Expected $BgExe after install, not found." }

Write-Host '[3] Registering the scheduled export...'
$TaskAction   = New-ScheduledTaskAction -Execute $BgExe -Argument 'export'
$TaskTriggers = @(
    (New-ScheduledTaskTrigger -Daily -At '12:00'),
    (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME)
)
# A first export of a large history takes minutes; an hour bounds a hung run.
$TaskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder `
    -Action $TaskAction -Trigger $TaskTriggers -Settings $TaskSettings `
    -RunLevel Limited -Force `
    -Description 'Copies new Claude Code transcripts into the usage-insights store' | Out-Null
Write-Host "Registered $TaskFolder$TaskName (daily 12:00 and at logon)"

Write-Host ''
Write-Host 'Done. Run `usage-insights` to open the dashboard.'
Write-Host "Store: $StorePath"
