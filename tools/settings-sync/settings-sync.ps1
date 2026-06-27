# settings-sync.ps1
# Mirrors the newer of two JSON files to the older one,
# preserving excluded key paths in the destination file.
#
# $ExcludePaths accepts dot-notation paths, e.g.:
#   "userId"                  -> top-level key
#   "settings.local.theme"    -> nested key

param(
    [string]$FileA = "C:\Path\To\first.json",
    [string]$FileB = "C:\Path\To\second.json",

    [string[]]$ExcludePaths = @(
        "statusLine.command"
        #"userId",
        #"deviceId",
        #"settings.local.theme"
        # add more paths here
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- helpers ---

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

# --- main ---

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

$src = Get-Content $srcPath -Raw | ConvertFrom-Json
$dst = Get-Content $dstPath -Raw | ConvertFrom-Json

# Parse exclude paths once
$parsedPaths = $ExcludePaths | ForEach-Object { ,($_ -split '\.') }

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
