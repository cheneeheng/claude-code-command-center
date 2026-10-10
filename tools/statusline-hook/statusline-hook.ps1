# Claude Code statusline (PowerShell port). Runs on Windows PowerShell 5.1 and PowerShell 7.
#
#   Opus 5.5 high   ctx [context gauge] 42% . 1h 12m . $1.23
#                   5h  [5-hour gauge]  63%  reset 16:00
#                   7d  [7-day gauge]   85%  reset Thu 16:00
#
# Reads the JSON Claude Code pipes to stdin. A rate-limit row is shown only when Claude Code
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
$HEAVY = [string][char]0x2501  # filled bar segment
$LIGHT = [string][char]0x2500  # empty bar segment
$SEP   = " $DIM$([char]0x00B7)$RESET "
$CYCLE = [char]0x21BA          # reset arrow
$DAYS  = 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'

function Get-Level([long]$p) {
    if ($p -lt 50) { "$ESC[32m" } elseif ($p -lt 80) { "$ESC[33m" } else { "$ESC[31m" }
}

function Get-Gauge($value) {
    $p = if ($null -eq $value) { [long]0 } else { [long][math]::Floor([double]$value) }
    $fill = [long][math]::Floor([math]::Min([math]::Max($p, 0), 100) * 10 / 100)
    $level = Get-Level $p
    "$level$($HEAVY * $fill)$RESET$DIM$($LIGHT * (10 - $fill))$RESET $level$p%$RESET"
}

function Get-Reset($resetsAt, [bool]$withDay) {
    if ($null -eq $resetsAt -or [double]$resetsAt -le 0) { return '' }
    $t = [DateTimeOffset]::FromUnixTimeSeconds([long][math]::Floor([double]$resetsAt)).ToLocalTime()
    $day = if ($withDay) { $DAYS[[int]$t.DayOfWeek] + ' ' } else { '' }
    "  $DIM$CYCLE $day$($t.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture))$RESET"
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

    $model  = if ($null -eq $data.model.display_name) { '' } else { [string]$data.model.display_name }
    $effort = if ($null -eq $data.effort.level) { '' } else { [string]$data.effort.level }
    $label  = "$ESC[1m$ESC[36m$model$RESET"
    $width  = $model.Length
    if ($effort) {
        $label += " $ESC[36m$effort$RESET"
        $width += 1 + $effort.Length
    }
    # Claude Code trims leading whitespace from each row, so the indent opens with U+2800
    # (Braille blank): it renders as an empty cell but is not whitespace.
    $indent = [string][char]0x2800 + (' ' * ($width + 2))
    $rows = @(
        "$label   ${DIM}ctx$RESET " +
        (Get-Gauge $data.context_window.used_percentage) +
        $SEP + (Get-Runtime $data.cost.total_duration_ms) +
        $SEP + '$' + (Get-Cost $data.cost.total_cost_usd)
    )
    foreach ($w in @(@('5h', $data.rate_limits.five_hour, $false),
                     @('7d', $data.rate_limits.seven_day, $true))) {
        if ($null -eq $w[1]) { continue }
        $rows += "$indent$DIM$($w[0])$RESET  " + (Get-Gauge $w[1].used_percentage) +
                 (Get-Reset $w[1].resets_at $w[2])
    }
    # Write, not Write-Output: no trailing \r\n on Windows, one \n after each row.
    [Console]::Out.Write(($rows -join "`n") + "`n")
} catch {
    # Never let a bad payload break the statusline: print nothing.
}
exit 0
