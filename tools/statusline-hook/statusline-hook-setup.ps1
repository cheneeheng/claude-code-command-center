#!/usr/bin/env pwsh
# Combined install/uninstall for the statusline-hook.
# Copies the chosen script into the Claude config dir and wires it up as the
# `statusLine` command in settings.json (other keys are preserved).
# Usage:
#   .\statusline-hook-setup.ps1                          # install ps1 variant (default)
#   .\statusline-hook-setup.ps1 -Variant sh              # bash variant (needs jq)
#   .\statusline-hook-setup.ps1 -Action uninstall
#   .\statusline-hook-setup.ps1 -ClaudeDir D:\claude     # override config dir

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Which implementation to wire up (see README).
    [ValidateSet('ps1', 'sh')]
    [string]$Variant = 'ps1',

    # Claude config dir to install into (defaults to ~/.claude).
    [string]$ClaudeDir = (Join-Path $HOME ".claude")
)

$settingsPath = Join-Path $ClaudeDir "settings.json"
$scriptName   = "statusline-hook.$Variant"
$destScript   = Join-Path $ClaudeDir $scriptName
$source       = Join-Path $PSScriptRoot $scriptName

# Every script name an install of this hook has ever used, including the retired .py port.
$knownScripts = 'statusline-hook.ps1', 'statusline-hook.sh', 'statusline-hook.py'

# The statusLine command Claude Code runs each turn. Prefer PowerShell 7, fall back to 5.1.
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$runnerFor = @{ ps1 = "$shell -NoProfile -File"; sh = "bash" }
$command   = '{0} "{1}"' -f $runnerFor[$Variant], $destScript

function Read-Settings {
    if (Test-Path $settingsPath) {
        $raw = Get-Content -Raw $settingsPath
        if ($raw.Trim()) { return $raw | ConvertFrom-Json }
    }
    return [pscustomobject]@{}
}

function Save-Settings($obj) {
    # -Depth 20 keeps nested settings (hooks, permissions) intact; pwsh writes BOM-less UTF-8.
    $obj | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding utf8
}

# Delete installed copies of this hook, except $Keep. Clears out other variants and the
# retired .py port so a reinstall leaves exactly one script behind.
function Remove-InstalledScripts([string]$Keep) {
    foreach ($name in $knownScripts) {
        if ($name -eq $Keep) { continue }
        $p = Join-Path $ClaudeDir $name
        if (Test-Path $p) {
            Remove-Item -Force $p
            Write-Host "Removed $p"
        }
    }
}

function Install-StatusLine {
    if (-not (Test-Path $source)) {
        throw "Hook script not found: $source"
    }
    if (-not (Test-Path $ClaudeDir)) {
        New-Item -ItemType Directory -Force $ClaudeDir | Out-Null
        Write-Host "Created $ClaudeDir"
    }

    Copy-Item -Force $source $destScript
    Write-Host "Installed hook to $destScript"
    Remove-InstalledScripts -Keep $scriptName

    $settings = Read-Settings
    $value = [pscustomobject]@{ type = "command"; command = $command }
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $value -Force
    Save-Settings $settings
    Write-Host "Wired statusLine -> $command in $settingsPath"

    if ($Variant -eq 'sh' -and -not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Warning "jq is not on PATH; the bash statusline prints nothing until jq is installed."
    }
}

function Uninstall-StatusLine {
    if (Test-Path $settingsPath) {
        $settings = Read-Settings
        if ($settings.PSObject.Properties.Name -contains 'statusLine') {
            $settings.PSObject.Properties.Remove('statusLine')
            Save-Settings $settings
            Write-Host "Removed statusLine from $settingsPath"
        } else {
            Write-Host "No statusLine key in $settingsPath — skipped"
        }
    } else {
        Write-Host "$settingsPath not found — skipped"
    }

    Remove-InstalledScripts -Keep ''
}

switch ($Action) {
    'install'   { Install-StatusLine }
    'uninstall' { Uninstall-StatusLine }
}
