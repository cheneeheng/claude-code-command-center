# sync-engine.ps1
# Generic newer-wins sync of a single file between two paths.
#
# Strategy:
#   raw         Copy the newer file over the older verbatim (plain text, no parsing).
#   json-merge  Copy the newer JSON over the older, but preserve $ExcludePaths keys
#               (dot-notation) from the destination — for machine-specific settings.
#
# $ExcludePaths is comma-separated (json-merge only), e.g.:
#   "statusLine.command,userId,settings.local.theme"

param(
    [Parameter(Mandatory)][string]$FileA,
    [Parameter(Mandatory)][string]$FileB,

    [ValidateSet('raw', 'json-merge')]
    [string]$Strategy = 'raw',

    # Comma-separated dot-notation key paths to preserve in the destination (json-merge only).
    # A single string (not string[]) so it round-trips cleanly through the VBS command line.
    [string]$ExcludePaths = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- json-merge helpers ---

function Get-NestedValue {
    param($obj, [string[]]$keys)
    $cur = $obj
    foreach ($k in $keys) {
        if ($null -eq $cur -or -not $cur.PSObject.Properties[$k]) { return $null }
        $cur = $cur.$k
    }
    return $cur
}

function Set-NestedValue {
    param($obj, [string[]]$keys, $value)
    $cur = $obj
    for ($i = 0; $i -lt $keys.Count - 1; $i++) {
        $k = $keys[$i]
        if (-not $cur.PSObject.Properties[$k]) {
            $cur | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $cur = $cur.$k
    }
    $last = $keys[-1]
    $cur | Add-Member -NotePropertyName $last -NotePropertyValue $value -Force
}

function Remove-NestedKey {
    param($obj, [string[]]$keys)
    $cur = $obj
    for ($i = 0; $i -lt $keys.Count - 1; $i++) {
        $k = $keys[$i]
        if ($null -eq $cur -or -not $cur.PSObject.Properties[$k]) { return }
        $cur = $cur.$k
    }
    $last = $keys[-1]
    if ($cur.PSObject.Properties[$last]) {
        $cur.PSObject.Properties.Remove($last)
    }
}

# --- pick newer (shared by every strategy) ---

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

# --- apply (the only part that differs per strategy) ---

if ($Strategy -eq 'raw') {
    Copy-Item -Path $srcPath -Destination $dstPath -Force
    exit 0
}

# json-merge
$src = Get-Content $srcPath -Raw | ConvertFrom-Json
$dst = Get-Content $dstPath -Raw | ConvertFrom-Json

# Parse exclude paths once (skip blanks from empty / trailing-comma input)
$parsedPaths = $ExcludePaths -split ',' |
    Where-Object { $_.Trim() } |
    ForEach-Object { ,($_.Trim() -split '\.') }

# Snapshot excluded values from destination
$snapshots = @{}
foreach ($keys in $parsedPaths) {
    $val = Get-NestedValue -obj $dst -keys $keys
    $snapshots[$keys -join '.'] = $val
}

# Deep-clone source, strip excluded keys, restore destination values
$merged = $src | ConvertTo-Json -Depth 100 | ConvertFrom-Json

foreach ($keys in $parsedPaths) {
    Remove-NestedKey -obj $merged -keys $keys
}

foreach ($keys in $parsedPaths) {
    $val = $snapshots[$keys -join '.']
    if ($null -ne $val) {
        Set-NestedValue -obj $merged -keys $keys -value $val
    }
}

$merged | ConvertTo-Json -Depth 100 | Set-Content -Path $dstPath -Encoding UTF8
