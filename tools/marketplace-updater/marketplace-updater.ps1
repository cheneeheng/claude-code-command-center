# marketplace-updater.ps1
#
# Refreshes the configured Claude Code marketplaces, then updates the plugins from those
# marketplaces that are installed for the configured repos (local or project scope).
#
#   1. claude plugin marketplace update <marketplace>        (once per marketplace)
#   2. claude plugin list --json                             (which plugins sit in which repo)
#   3. claude plugin update <plugin>@<marketplace> --scope <scope>   (run from inside the repo)
#
# Config (JSON, re-read every run): { "marketplaces": ["name", ...], "repos": ["path", ...] }
#
# Parameters:
#   -ConfigFile     Path to the JSON config. Default: config.json next to this script.
#   -ClaudeCommand  The claude CLI to call. Default: claude. Tests point it at a stub.
#   -DryRun         Log what would run; change nothing.
#
# Exit codes: 0 = all done, 1 = fatal (no/invalid config), 2 = ran, but a step failed.

param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'config.json'),
    [string]$ClaudeCommand = 'claude',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path (Split-Path -Parent $ConfigFile) 'run.log'

# Write-Host (not Write-Output) so a function that logs can also return a value.
function Log([string]$Msg) {
    $line = '[{0}] [marketplace-updater] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-FullPath([string]$Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') }

if (-not (Test-Path $ConfigFile)) { Write-Host "Config not found: $ConfigFile"; exit 1 }
$cfg = Get-Content -Raw $ConfigFile | ConvertFrom-Json
$marketplaces = @($cfg.marketplaces | Where-Object { $_ })
$repos = @($cfg.repos | Where-Object { $_ } | ForEach-Object { Get-FullPath $_ })
if (-not $marketplaces -or -not $repos) {
    Log "Config needs non-empty 'marketplaces' and 'repos': $ConfigFile"
    exit 1
}

# Unattended: never let a plugin update wait on a prompt. No -y is passed, so an update that
# needs a marketplace-declared command confirmed fails here and is left for a person.
$failed = 0

# Same pipe-then-$LASTEXITCODE shape for every call: echo the CLI output, return its exit code.
function Invoke-Claude([string[]]$CliArgs) {
    & $ClaudeCommand @CliArgs 2>&1 | ForEach-Object { Log "    $_" }
    $LASTEXITCODE
}

$refreshed = @()
foreach ($m in $marketplaces) {
    if ($DryRun) { Log "would run: claude plugin marketplace update $m"; $refreshed += $m; continue }
    Log "Refreshing marketplace $m"
    if ((Invoke-Claude 'plugin', 'marketplace', 'update', $m) -eq 0) { $refreshed += $m }
    else { Log "FAILED refreshing marketplace $m - its plugins are skipped"; $failed++ }
}

$listOut = & $ClaudeCommand plugin list --json 2>$null
$listCode = $LASTEXITCODE
try { $installed = @(($listOut -join "`n") | ConvertFrom-Json -ErrorAction Stop) } catch { $installed = $null }
if ($listCode -ne 0 -or $null -eq $installed) {
    # Not "nothing to update": a broken list would otherwise stop all updates silently.
    Log "FAILED listing installed plugins (exit $listCode)"
    Log "Done. $($failed + 1) failure(s)."
    exit 2
}

$seen = @{}
$done = @{}
foreach ($p in $installed) {
    if ($p.scope -notin 'local', 'project' -or -not $p.projectPath) { continue }
    # Use the configured spelling of the repo: the list may differ in case (drive letter).
    $repo = @($repos | Where-Object { $_ -eq (Get-FullPath $p.projectPath) })[0]
    $market = $p.id.Substring($p.id.LastIndexOf('@') + 1)
    if (-not $repo -or $refreshed -notcontains $market) { continue }
    $key = "$($repo.ToLowerInvariant())|$($p.id)|$($p.scope)"
    if ($done[$key]) { continue }   # the list can hold one install twice
    $done[$key] = $true
    $seen[$repo] = $true

    if ($DryRun) { Log "would run in ${repo}: claude plugin update $($p.id) --scope $($p.scope)"; continue }
    if (-not (Test-Path $repo)) { Log "FAILED $($p.id): repo folder is missing: $repo"; $failed++; continue }
    Log "Updating $($p.id) ($($p.scope)) in $repo"
    Push-Location $repo
    try { $code = Invoke-Claude 'plugin', 'update', $p.id, '--scope', $p.scope }
    finally { Pop-Location }
    if ($code -ne 0) { Log "FAILED $($p.id) in ${repo}: exit $code"; $failed++ }
}

foreach ($r in @($repos | Where-Object { -not $seen[$_] })) {
    Log "Nothing to update in ${r}: no local/project plugin from $($refreshed -join ', ') is installed there"
}

Log "Done. $failed failure(s)."
if ($failed -gt 0) { exit 2 }
