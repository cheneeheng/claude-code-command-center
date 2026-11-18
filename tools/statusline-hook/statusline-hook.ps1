# Claude Code statusline (PowerShell port). Runs on Windows PowerShell 5.1 and PowerShell 7.
#
#   Opus 5.5 high | [hourglass] 36m | ctx 42% | 5h 63% [reset] 7h 6m | 7d 85% [reset] 5d 7h | [clock] 1h 12m | $1.23
#
# Reads the JSON Claude Code pipes to stdin. A rate-limit segment is shown only when Claude Code
# sends that window. Bad input prints nothing. The render spec is the fixtures/ folder;
# statusline-hook.sh must produce the same bytes.
#
# Setup: "statusLine": { "type": "command",
#          "command": "pwsh -NoProfile -File ~/.claude/statusline-hook.ps1" }
#
# This file is kept ASCII-only: PowerShell 5.1 reads a BOM-less script as ANSI, so every
# non-ASCII glyph is built from its code point.

$ESC   = [char]27
$RESET = "$ESC[0m"
$DIM   = "$ESC[2m"
$SEP   = " $DIM$([char]0x007C)$RESET "
$CYCLE = [char]0x21BA          # reset arrow
$CLOCK = [char]0x25F7          # runtime marker
$GLASS = [char]0x29D7          # cache expiry marker

function Get-Level([long]$p) {
    if ($p -lt 50) { "$ESC[32m" } elseif ($p -lt 80) { "$ESC[33m" } else { "$ESC[31m" }
}

# Percentage right-aligned in three characters, coloured by level.
function Get-Pct($value) {
    $p = if ($null -eq $value) { [long]0 } else { [long][math]::Floor([double]$value) }
    "$(Get-Level $p)$("$p".PadLeft(3))%$RESET"
}

# Time left until a reset, e.g. "5d 7h", "7h 6m", "12m".
function Get-Left([double]$seconds) {
    $s = [long][math]::Floor([math]::Max($seconds, 0))
    $d = [long][math]::Floor($s / 86400)
    $h = [long][math]::Floor(($s % 86400) / 3600)
    $m = [long][math]::Floor(($s % 3600) / 60)
    if ($d -gt 0) { "${d}d ${h}h" } elseif ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
}

function Get-Reset($resetsAt) {
    if ($null -eq $resetsAt -or [double]$resetsAt -le 0) { return '' }
    " $DIM$CYCLE $(Get-Left ([long][math]::Floor([double]$resetsAt) - $NOW))$RESET"
}

# The main session caches its prompt for one hour after its last API reply. Synthetic
# replies never reached the API, and sidechain replies belong to subagents.
# less-code: only the last 100 transcript lines are scanned. If the last main-session reply
# is further back, the cache segment is left out.
function Get-Cache($path) {
    if (-not $path) { return '' }
    $at = $null
    try {
        foreach ($line in (Get-Content -LiteralPath $path -Tail 100 -Encoding UTF8 -ErrorAction Stop)) {
            if ($line -notmatch '"type":"assistant"') { continue }
            try { $e = $line | ConvertFrom-Json } catch { continue }
            if ($e.type -eq 'assistant' -and $e.isSidechain -ne $true -and
                $e.message.model -ne '<synthetic>' -and $null -ne $e.timestamp) { $at = $e.timestamp }
        }
        if ($null -eq $at) { return '' }
        # PowerShell 7 parses ISO timestamps into a UTC DateTime; 5.1 leaves a string.
        $t = if ($at -is [datetime]) { [DateTimeOffset]$at }
             else { [DateTimeOffset]::Parse([string]$at, [Globalization.CultureInfo]::InvariantCulture) }
        $end = $t.ToUnixTimeSeconds() + 3600
    } catch { return '' }
    $state = if ($end -gt $NOW) { Get-Left ($end - $NOW) } else { 'expired' }
    "$DIM$GLASS$RESET $state"
}

function Get-Runtime($ms) {
    $s = if ($null -eq $ms) { [long]0 } else { [long][math]::Floor([double]$ms / 1000) }
    $h = [long][math]::Floor($s / 3600)
    $m = [long][math]::Floor(($s % 3600) / 60)
    if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
}

function Get-Cost($usd) {
    $usd = if ($null -eq $usd) { 0.0 } else { [double]$usd }
    $cents = [long][math]::Floor($usd * 100 + 0.5)
    "$([long][math]::Floor($cents / 100)).$(($cents % 100).ToString('00'))"
}

try {
    [Console]::InputEncoding  = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ($data -isnot [System.Management.Automation.PSCustomObject]) { exit 0 }
    # C4_STATUSLINE_NOW (epoch seconds) pins the clock for the golden tests only.
    $NOW = if ($env:C4_STATUSLINE_NOW) { [double]$env:C4_STATUSLINE_NOW }
           else { [double][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

    $model  = if ($null -eq $data.model.display_name) { '' } else { [string]$data.model.display_name }
    $effort = if ($null -eq $data.effort.level) { '' } else { [string]$data.effort.level }
    $label  = "$ESC[1m$ESC[36m$model$RESET"
    if ($effort) { $label += " $ESC[36m$effort$RESET" }
    # Segments are joined by the separator, so an absent one leaves no stray separator.
    $segs = @($label, (Get-Cache $data.transcript_path),
              ("${DIM}ctx$RESET" + (Get-Pct $data.context_window.used_percentage)))
    foreach ($w in @(@('5h', $data.rate_limits.five_hour), @('7d', $data.rate_limits.seven_day))) {
        if ($null -eq $w[1]) { continue }
        $segs += "$DIM$($w[0])$RESET" + (Get-Pct $w[1].used_percentage) + (Get-Reset $w[1].resets_at)
    }
    $segs += "$DIM$CLOCK$RESET " + (Get-Runtime $data.cost.total_duration_ms)
    $segs += '$' + (Get-Cost $data.cost.total_cost_usd)
    # Write, not Write-Output: no trailing \r\n on Windows, one \n after the line.
    [Console]::Out.Write((($segs | Where-Object { $_ }) -join $SEP) + "`n")
} catch {
    # Never let a bad payload break the statusline: print nothing.
}

# Quota export, on unless C4_STATUSLINE_DISABLE_EXPORT is on: hooks never receive rate_limits, so
# the latest reading is relayed to one file for readers such as the ceh-every-session usage-limit
# guard. Written after the statusline is printed, through a temp file and a rename, so a reader
# never sees half a line and a failure never changes the output. WriteAllText with a BOM-less
# UTF8Encoding, because 5.1's Out-File and Set-Content write UTF-16 or ANSI.
$tmp = $null
try {
    if ($env:C4_STATUSLINE_DISABLE_EXPORT -notin @('1', 'true', 'yes') -and
        $data -is [System.Management.Automation.PSCustomObject] -and
        $data.rate_limits -is [System.Management.Automation.PSCustomObject] -and
        @($data.rate_limits.PSObject.Properties).Count -gt 0) {
        $root = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $dir = Join-Path $root '.claude/statusline/latest'
        $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop
        $json = [ordered]@{
            session_id = $data.session_id
            ts         = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            data       = @{ rate_limits = $data.rate_limits }
        } | ConvertTo-Json -Compress -Depth 10
        $tmp = Join-Path $dir "rate-limits.jsonl.$PID.tmp"
        [IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination (Join-Path $dir 'rate-limits.jsonl') -Force -ErrorAction Stop
    }
} catch {
    if ($tmp) { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}
exit 0
