# Runs sync-engine.ps1 -Strategy json-merge on temp files and checks the destination.
# Usage: pwsh -NoProfile -File tests/json-merge.ps1   (exit 1 on any failure)

$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot '../sync-engine.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) "file-sync-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$failed = 0

# Syncs $Src (newer) over $Dst and compares the result, compressed, with $Expected.
function Test-Merge([string]$Name, [string]$Src, [string]$Dst, [string]$Exclude, [string]$Expected) {
    $a = Join-Path $tmp 'src.json'; $b = Join-Path $tmp 'dst.json'
    Set-Content $a $Src; Set-Content $b $Dst
    (Get-Item $b).LastWriteTime = (Get-Item $a).LastWriteTime.AddMinutes(-1)
    & pwsh -NoProfile -File $engine -FileA $a -FileB $b -Strategy json-merge -ExcludePaths $Exclude
    $actual = Get-Content -Raw $b | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress
    if ($actual -ceq $Expected) { Write-Host "ok   $Name" }
    else { Write-Host "FAIL $Name`n  expected: $Expected`n  actual:   $actual"; $script:failed++ }
}

$hook = '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"DST"}]}]}}'
$path = 'hooks.PreToolUse[0].hooks[0].command'

Test-Merge 'source without the indexed array adds no object in its place' `
    '{"hooks":{"Stop":[]}}' $hook $path '{"hooks":{"Stop":[]}}'

Test-Merge 'source without the parent key adds nothing' `
    '{"x":1}' $hook $path '{"x":1}'

Test-Merge 'source array element without the nested array adds nothing' `
    '{"hooks":{"PreToolUse":[{"matcher":"Bash"}]}}' $hook $path '{"hooks":{"PreToolUse":[{"matcher":"Bash"}]}}'

Test-Merge 'source with the indexed array keeps the destination value' `
    '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"SRC"}]}]}}' $hook $path `
    '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"DST"}]}]}}'

Test-Merge 'object-only path is still created when the source lacks it' `
    '{"x":1}' '{"statusLine":{"command":"DST"}}' 'statusLine.command' '{"x":1,"statusLine":{"command":"DST"}}'

Remove-Item -Recurse -Force $tmp
if ($failed) { Write-Host "$failed failed"; exit 1 }
Write-Host 'all passed'
