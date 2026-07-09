# sync-engine.ps1
# Generic newer-wins sync of a single file between two paths.
#
# Strategy:
#   raw         Copy the newer file over the older verbatim (plain text, no parsing).
#   json-merge  Copy the newer JSON over the older, but preserve $ExcludePaths keys
#               (dot-notation) from the destination — for machine-specific settings.
#
# $ExcludePaths is comma-separated (json-merge only), dot-notation with optional
# [n] array indices, e.g.:
#   "statusLine.command,userId,hooks.PreToolUse[0].hooks[0].command"

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

# Parses a dot-notation path into steps, each a Prop (object key) or an
# Index (array position), so paths can reach into arrays, e.g.
# "hooks.PreToolUse[0].hooks[0].command".
function ConvertTo-PathSteps {
    param([string]$Path)
    $steps = @()
    foreach ($segment in $Path -split '\.') {
        if ($segment -notmatch '^([^\[\]]+)((?:\[\d+\])*)$') {
            throw "Invalid ExcludePaths segment: '$segment'"
        }
        $steps += [pscustomobject]@{ Type = 'Prop'; Name = $matches[1] }
        foreach ($idx in [regex]::Matches($matches[2], '\[(\d+)\]')) {
            $steps += [pscustomobject]@{ Type = 'Index'; Index = [int]$idx.Groups[1].Value }
        }
    }
    return $steps
}

function Get-NestedValue {
    param($obj, $steps)
    $cur = $obj
    foreach ($step in $steps) {
        if ($null -eq $cur) { return $null }
        if ($step.Type -eq 'Prop') {
            if (-not $cur.PSObject.Properties[$step.Name]) { return $null }
            $cur = $cur.($step.Name)
        } else {
            if ($step.Index -ge $cur.Count) { return $null }
            $cur = $cur[$step.Index]
        }
    }
    return $cur
}

function Set-NestedValue {
    param($obj, $steps, $value)
    $cur = $obj
    for ($i = 0; $i -lt $steps.Count - 1; $i++) {
        $step = $steps[$i]
        if ($step.Type -eq 'Prop') {
            if (-not $cur.PSObject.Properties[$step.Name]) {
                $cur | Add-Member -NotePropertyName $step.Name -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cur = $cur.($step.Name)
        } else {
            # Arrays are not auto-vivified — the index must already exist.
            if ($step.Index -ge $cur.Count) { return }
            $cur = $cur[$step.Index]
        }
    }
    $last = $steps[-1]
    if ($last.Type -eq 'Prop') {
        $cur | Add-Member -NotePropertyName $last.Name -NotePropertyValue $value -Force
    } elseif ($last.Index -lt $cur.Count) {
        $cur[$last.Index] = $value
    }
}

function Remove-NestedKey {
    param($obj, $steps)
    $cur = $obj
    for ($i = 0; $i -lt $steps.Count - 1; $i++) {
        $step = $steps[$i]
        if ($null -eq $cur) { return }
        if ($step.Type -eq 'Prop') {
            if (-not $cur.PSObject.Properties[$step.Name]) { return }
            $cur = $cur.($step.Name)
        } else {
            if ($step.Index -ge $cur.Count) { return }
            $cur = $cur[$step.Index]
        }
    }
    $last = $steps[-1]
    if ($last.Type -eq 'Prop') {
        if ($cur.PSObject.Properties[$last.Name]) {
            $cur.PSObject.Properties.Remove($last.Name)
        }
    }
    # Array elements are left as-is: removing by index would shift positions,
    # and Set-NestedValue overwrites the slot afterwards when a value exists.
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
    ForEach-Object { $_.Trim() }

# Snapshot excluded values from destination
$snapshots = @{}
foreach ($path in $parsedPaths) {
    $steps = ConvertTo-PathSteps -Path $path
    $snapshots[$path] = @{ Steps = $steps; Value = (Get-NestedValue -obj $dst -steps $steps) }
}

# Deep-clone source, strip excluded keys, restore destination values
$merged = $src | ConvertTo-Json -Depth 100 | ConvertFrom-Json

foreach ($path in $parsedPaths) {
    Remove-NestedKey -obj $merged -steps $snapshots[$path].Steps
}

foreach ($path in $parsedPaths) {
    $val = $snapshots[$path].Value
    if ($null -ne $val) {
        Set-NestedValue -obj $merged -steps $snapshots[$path].Steps -value $val
    }
}

$merged | ConvertTo-Json -Depth 100 | Set-Content -Path $dstPath -Encoding UTF8
