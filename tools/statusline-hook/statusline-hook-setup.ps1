#!/usr/bin/env pwsh
# Combined install/uninstall for the statusline-hook.
# Copies the chosen hook script into the Claude config dir and wires it up as the
# `statusLine` command in settings.json (other keys are preserved).
# Usage:
#   .\statusline-hook-setup.ps1                          # install ps1 variant (default)
#   .\statusline-hook-setup.ps1 -Variant py
#   .\statusline-hook-setup.ps1 -Action uninstall
#   .\statusline-hook-setup.ps1 -ClaudeDir D:\claude     # override config dir

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Which implementation to wire up (see README).
    [ValidateSet('ps1', 'sh', 'py')]
    [string]$Variant = 'ps1',

    # Claude config dir to install into (defaults to ~/.claude).
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE ".claude")
)

$settingsPath = Join-Path $ClaudeDir "settings.json"
$scriptName   = "statusline-hook.$Variant"
$destScript   = Join-Path $ClaudeDir $scriptName
$source       = Join-Path $PSScriptRoot $scriptName

# The statusLine command Claude Code runs each turn — points at the installed hook so
# each install (any config dir) runs and exports from its own copy.
$runnerFor = @{ ps1 = "pwsh -NoProfile -File"; sh = "bash"; py = "python3" }
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

    $settings = Read-Settings
    $value = [pscustomobject]@{ type = "command"; command = $command }
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $value -Force
    Save-Settings $settings
    Write-Host "Wired statusLine -> $command in $settingsPath"

    if ($Variant -eq 'sh') { Write-Host "Note: the .sh hook requires 'jq' on PATH." }
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

    # Remove whichever variant script we may have copied in.
    foreach ($v in @('ps1', 'sh', 'py')) {
        $p = Join-Path $ClaudeDir "statusline-hook.$v"
        if (Test-Path $p) {
            Remove-Item -Force $p
            Write-Host "Removed $p"
        }
    }
}

switch ($Action) {
    'install'   { Install-StatusLine }
    'uninstall' { Uninstall-StatusLine }
}
