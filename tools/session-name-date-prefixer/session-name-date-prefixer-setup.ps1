#!/usr/bin/env pwsh
# Combined install/uninstall for the claude session-name wrapper.
# Usage:
#   .\session-name-date-prefixer-setup.ps1            # install (default)
#   .\session-name-date-prefixer-setup.ps1 -Action install
#   .\session-name-date-prefixer-setup.ps1 -Action uninstall

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install'
)

$binDir  = "$env:LOCALAPPDATA\claude-automation\cc-inject-date-to-session-name"
$wrapper = "$binDir\claude.ps1"
$source  = Join-Path $PSScriptRoot "session-name-date-prefixer.ps1"

function Install-Wrapper {
    # 1. Create bin dir
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Force $binDir | Out-Null
        Write-Host "Created $binDir"
    }

    # 2. Copy wrapper
    Copy-Item -Force $source $wrapper
    Write-Host "Installed wrapper to $wrapper"

    # 3. Prepend to user PATH if not already present
    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $dirs    = $current -split ';' | Where-Object { $_ -ne '' }

    if ($binDir -notin $dirs) {
        [Environment]::SetEnvironmentVariable('PATH', "$binDir;$current", 'User')
        Write-Host "Added $binDir to user PATH"
    } else {
        Write-Host "$binDir already on user PATH — skipped"
    }

    # 4. Verify the real claude binary exists somewhere else on PATH
    $realClaude = Get-Command claude -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*claude.ps1' } |
        Select-Object -First 1

    if ($realClaude) {
        Write-Host "Real claude found at: $($realClaude.Source)"
    } else {
        Write-Warning "Real claude binary not found on PATH. Install Claude Code first."
    }

    Write-Host ""
    Write-Host "Done. Open a new terminal for PATH changes to take effect."
}

function Uninstall-Wrapper {
    # 1. Remove wrapper file
    if (Test-Path $wrapper) {
        Remove-Item -Force $wrapper
        Write-Host "Removed wrapper $wrapper"
    } else {
        Write-Host "Wrapper not found at $wrapper — skipped"
    }

    # 2. Remove bin dir if empty
    if ((Test-Path $binDir) -and -not (Get-ChildItem -Force $binDir)) {
        Remove-Item -Force $binDir
        Write-Host "Removed empty $binDir"
    }

    # 3. Strip binDir from user PATH
    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $dirs    = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne $binDir }
    $new     = $dirs -join ';'

    if ($new -ne $current) {
        [Environment]::SetEnvironmentVariable('PATH', $new, 'User')
        Write-Host "Removed $binDir from user PATH"
    } else {
        Write-Host "$binDir not on user PATH — skipped"
    }

    Write-Host ""
    Write-Host "Done. Open a new terminal for PATH changes to take effect."
}

switch ($Action) {
    'install'   { Install-Wrapper }
    'uninstall' { Uninstall-Wrapper }
}
