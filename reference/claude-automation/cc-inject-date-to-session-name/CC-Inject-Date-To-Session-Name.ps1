#!/usr/bin/env pwsh
# Claude wrapper — auto-injects --name <dir>-<timestamp> if not already supplied
# Install: place in a directory on your PATH *before* the real claude binary
#          e.g. $env:LOCALAPPDATA\claude-automation\cc-inject-date-to-session-name\claude.ps1  (add that dir to $env:PATH)

$hasName = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '-n' -or $args[$i] -eq '--name') {
        $hasName = $true
        break
    }
}

if (-not $hasName) {
    $dirName  = (Split-Path -Leaf (Get-Location)) -replace '[^a-zA-Z0-9_-]', '-'
    $stamp    = Get-Date -Format 'yyMMddHHmm'
    $autoName = "$dirName-$stamp"
    $argList  = @('--name', $autoName) + $args
} else {
    $argList = $args
}

# Resolve the real claude binary (skip this script itself)
$realClaude = Get-Command claude -All |
    Where-Object { $_.Source -notlike '*claude.ps1' } |
    Select-Object -First 1 -ExpandProperty Source

if (-not $realClaude) {
    Write-Error "claude binary not found on PATH"
    exit 1
}

& $realClaude @argList
