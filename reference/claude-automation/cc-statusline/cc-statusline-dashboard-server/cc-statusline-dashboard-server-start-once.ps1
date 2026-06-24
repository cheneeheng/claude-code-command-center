# Starts cc-statusline-dashboard-server.py only if no instance is already listening on the port.
# Used as the scheduled task action so duplicate launches are safe.

param([int]$Port = 8080)

$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) { exit 0 }

$pythonExe  = (python -c "import sys; print(sys.executable)")
$scriptPath = Join-Path $PSScriptRoot "cc-statusline-dashboard-server.py"
$claudeDir1 = Join-Path $env:USERPROFILE ".claude"
$claudeDir2 = Join-Path $env:USERPROFILE ".claude_devcontainer"

Start-Process -FilePath $pythonExe `
    -ArgumentList "`"$scriptPath`"", "--claude-dir", "`"$claudeDir1`"", "`"$claudeDir2`"" `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden
