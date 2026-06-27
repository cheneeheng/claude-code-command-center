# claude-md-sync.ps1
# Mirrors the newer CLAUDE.md to the older one (plain-text, no merge logic needed).

param(
    [string]$FileA = "C:\Path\To\.claude\CLAUDE.md",
    [string]$FileB = "C:\Path\To\.claude_mirror\CLAUDE.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $FileA)) { throw "FileA not found: $FileA" }
if (-not (Test-Path $FileB)) { throw "FileB not found: $FileB" }

$a = Get-Item $FileA
$b = Get-Item $FileB

if ($a.LastWriteTime -eq $b.LastWriteTime) { exit 0 }

if ($a.LastWriteTime -gt $b.LastWriteTime) {
    $srcPath = $FileA
    $dstPath = $FileB
} else {
    $srcPath = $FileB
    $dstPath = $FileA
}

Copy-Item -Path $srcPath -Destination $dstPath -Force
