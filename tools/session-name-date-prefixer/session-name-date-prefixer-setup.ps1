#!/usr/bin/env pwsh
# Install/uninstall the SessionStart hook that names each new session <folder>-<yyMMddHHmm>.
# The hook lives in settings.json; other keys and hooks are preserved.
# Usage:
#   .\session-name-date-prefixer-setup.ps1                        # install (default)
#   .\session-name-date-prefixer-setup.ps1 -Action uninstall
#   .\session-name-date-prefixer-setup.ps1 -ClaudeDir D:\claude   # override config dir

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Claude config dir to install into (defaults to ~/.claude).
    [string]$ClaudeDir = (Join-Path $HOME '.claude')
)

$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $ClaudeDir 'settings.json'
$marker       = 'session-name-date-prefixer'

# Runs through "shell": "powershell", which is not documented as pwsh or powershell.exe, so it
# stays valid in both. Prints nothing when the session already has a title the user gave
# (--name, /rename). A title in this hook's own <folder>-<10 digits> form, which /clear
# inherits, is replaced. The leading no-op names the tool, so install and uninstall can find it.
$command = @'
$null = 'session-name-date-prefixer'; $n = (Split-Path -Leaf (Get-Location)) -replace '[^A-Za-z0-9_-]', '-'; $t = ([Console]::In.ReadToEnd() | ConvertFrom-Json).session_title; if (-not $t -or $t -cmatch "^$n-\d{10}$") { '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"' + $n + '-' + (Get-Date -Format yyMMddHHmm) + '"}}' }
'@

# The retired PATH wrapper this hook replaces (Windows only, hence the LOCALAPPDATA guard).
$oldBinDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'claude-automation\cc-inject-date-to-session-name' }

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

# SessionStart groups that are not ours. @() keeps a one-item result an array, so
# ConvertTo-Json still writes SessionStart as a JSON array.
function Get-OtherGroups($settings) {
    if (-not $settings.hooks -or -not $settings.hooks.SessionStart) { return @() }
    @($settings.hooks.SessionStart | Where-Object {
        -not @($_.hooks | Where-Object { $_.command -like "*$marker*" })
    })
}

function Remove-OldWrapper {
    if (-not $oldBinDir) { return }
    if (Test-Path $oldBinDir) {
        Remove-Item -Recurse -Force $oldBinDir
        Write-Host "Removed the old wrapper folder $oldBinDir"
    }
    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $dirs    = @($current -split ';' | Where-Object { $_ -ne '' })
    if ($dirs -contains $oldBinDir) {
        $new = ($dirs | Where-Object { $_ -ne $oldBinDir }) -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $new, 'User')
        Write-Host "Removed $oldBinDir from the user PATH (open a new terminal to pick it up)"
    }
}

function Install-Hook {
    if (-not (Test-Path $ClaudeDir)) {
        New-Item -ItemType Directory -Force $ClaudeDir | Out-Null
        Write-Host "Created $ClaudeDir"
    }
    $settings = Read-Settings
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $ours = [pscustomobject]@{
        matcher = 'startup|clear'
        hooks   = @([pscustomobject]@{ type = 'command'; shell = 'powershell'; command = $command })
    }
    $groups = @(Get-OtherGroups $settings) + $ours
    $settings.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue $groups -Force
    Save-Settings $settings
    Write-Host "Added the SessionStart hook to $settingsPath"
    Remove-OldWrapper
}

function Uninstall-Hook {
    if (Test-Path $settingsPath) {
        $settings = Read-Settings
        $groups = @(Get-OtherGroups $settings)
        if ($settings.hooks -and $settings.hooks.SessionStart -and
            $groups.Count -lt @($settings.hooks.SessionStart).Count) {
            if ($groups.Count) {
                $settings.hooks.SessionStart = $groups
            } else {
                $settings.hooks.PSObject.Properties.Remove('SessionStart')
                if (-not $settings.hooks.PSObject.Properties.Name) {
                    $settings.PSObject.Properties.Remove('hooks')
                }
            }
            Save-Settings $settings
            Write-Host "Removed the SessionStart hook from $settingsPath"
        } else {
            Write-Host "No session-name hook in $settingsPath, skipped"
        }
    } else {
        Write-Host "$settingsPath not found, skipped"
    }
    Remove-OldWrapper
}

switch ($Action) {
    'install'   { Install-Hook }
    'uninstall' { Uninstall-Hook }
}
