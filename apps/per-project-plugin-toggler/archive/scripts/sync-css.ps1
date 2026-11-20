# Anchored to the repo root so this works from any cwd (npm runs it from vscode-extension/).
$repoRoot = Split-Path -Parent $PSScriptRoot

Copy-Item -Path (Join-Path $repoRoot "html\styles.css") -Destination (Join-Path $repoRoot "vscode-extension\webview\styles.css") -Force
Write-Host "styles.css synced -> vscode-extension\webview\styles.css"

Copy-Item -Path (Join-Path $repoRoot "html\icon.svg") -Destination (Join-Path $repoRoot "vscode-extension\webview\icon.svg") -Force
Write-Host "icon.svg synced -> vscode-extension\webview\icon.svg"
