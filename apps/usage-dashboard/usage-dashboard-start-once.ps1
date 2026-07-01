# Starts usage-dashboard.py only if no instance is already listening on the port.
# Used as the scheduled task action so duplicate launches are safe.

param([int]$Port = 8080)

$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) { exit 0 }

$scriptPath = Join-Path $PSScriptRoot "usage-dashboard.py"
$claudeDir1 = Join-Path $env:USERPROFILE ".claude"
$claudeDir2 = Join-Path $env:USERPROFILE ".claude_devcontainer"

# Ensure the venv is present and in sync before launching.
& uv sync --project $PSScriptRoot

Start-Process -FilePath "uv" `
    -ArgumentList "run", "--project", "`"$PSScriptRoot`"", "python", "`"$scriptPath`"", "--claude-dir", "`"$claudeDir1`"", "`"$claudeDir2`"" `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden
