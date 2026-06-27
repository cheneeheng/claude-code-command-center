# Setup:
# "statusLine": {
#   "type": "command",
#   "command": "pwsh -NoProfile -File ~/.claude/statusline-hook.ps1",
#   "padding": 2
# }

# Force UTF-8 output so special characters render correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read JSON from stdin
$data = [Console]::In.ReadToEnd() | ConvertFrom-Json

# --- Extract fields ---
$model      = $data.model.id
$durationMs = if ($data.cost.total_duration_ms) { $data.cost.total_duration_ms } else { 0 }
$cost       = if ($data.cost.total_cost_usd) { $data.cost.total_cost_usd } else { 0 }
#$pct        = if ($data.context_window.used_percentage) { [int]$data.context_window.used_percentage } else { 0 }
#$pct        = if ($data.context_window.used_percentage) { [int]$data.context_window.used_percentage * 5 } else { 0 }
$pct = if ($data.context_window.used_percentage) {
    $raw = [int]$data.context_window.used_percentage
    if ($data.context_window.context_window_size -eq 1000000) {
        $raw * 5
    } else {
        $raw
    }
} else {
    0
}
$rate5h     = if ($data.rate_limits.five_hour.used_percentage) { [int]$data.rate_limits.five_hour.used_percentage } else { 0 }
$reset5h    = if ($data.rate_limits.five_hour.resets_at) { $data.rate_limits.five_hour.resets_at } else { 0 }
$rate7d     = if ($data.rate_limits.seven_day.used_percentage) { [int]$data.rate_limits.seven_day.used_percentage } else { 0 }
$reset7d    = if ($data.rate_limits.seven_day.resets_at) { $data.rate_limits.seven_day.resets_at } else { 0 }

# --- Format runtime ---
$totalSec = [int]($durationMs / 1000)
$hours    = [int]($totalSec / 3600)
$mins     = [int](($totalSec % 3600) / 60)
$secs     = $totalSec % 60
$runtime  = if ($hours -gt 0) { "${hours}h ${mins}m ${secs}s" } else { "${mins}m ${secs}s" }

# --- Format cost ---
$costFmt = '$' + $cost.ToString('0.0000')

# --- Build context bar (char codes avoid file encoding issues) ---
$barWidth   = 10
$pctCapped  = [math]::Min($pct, 100)
$filled     = [int]($pctCapped * $barWidth / 100)
#$filled     = [int]($pct * $barWidth / 100)
$empty      = $barWidth - $filled
$filledChar = [char]0x2593  # ▓
$emptyChar  = [char]0x2591  # ░
$resetSym   = [char]0x21BA  # ↺
$bar        = ($filledChar.ToString() * $filled) + ($emptyChar.ToString() * $empty)

# --- Format reset times ---
$reset5hFmt = if ($reset5h -gt 0) {
  [DateTimeOffset]::FromUnixTimeSeconds($reset5h).LocalDateTime.ToString('HH:mm')
} else { '--:--' }

$reset7dFmt = if ($reset7d -gt 0) {
  [DateTimeOffset]::FromUnixTimeSeconds($reset7d).LocalDateTime.ToString('ddd HH:mm')
} else { '---' }

# --- ANSI color codes ---
$Green  = "`e[32m"
$Yellow = "`e[33m"
$Red    = "`e[31m"
$Reset  = "`e[0m"

# Context: green <30, yellow 30-49, red >=50
$ctxColor = if ($pct -lt 30) { $Green } elseif ($pct -lt 50) { $Yellow } else { $Red }

# Rate limits: green <30, yellow 30-69, red >=70
function Get-RateColor($r) {
  if ($r -lt 30) { return $Green } elseif ($r -lt 70) { return $Yellow } else { return $Red }
}
$color5h = Get-RateColor $rate5h
$color7d = Get-RateColor $rate7d

# --- Single-line output ---
Write-Output "$model | ${ctxColor}${bar} ${pct}%${Reset} | $runtime | $costFmt | ${color5h}5H: $rate5h% ($resetSym $reset5hFmt)${Reset} | ${color7d}7D: $rate7d% ($resetSym $reset7dFmt)${Reset}"

# --- Log to per-project statusline/project_name/$session_id.jsonl ---
$claudeDir = if ($env:CLAUDE_DIR) {
    # Use the first dir if multiple are specified (pathsep-separated)
    ($env:CLAUDE_DIR -split [System.IO.Path]::PathSeparator)[0].Trim()
} else {
    Join-Path $env:USERPROFILE ".claude"
}

$sessionId = if ($data.session_id) { $data.session_id } else { "__unknown__" }
$cwd       = if ($data.cwd) { $data.cwd } else { $null }

# Encode cwd into the same dir-name format Claude Code uses (: and separators → -)
$projectDirName = $cwd -replace ':', '-' -replace '[/\\]', '-'
$logDir = Join-Path $claudeDir "statusline\$projectDirName"

try {
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $tsMs     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $logEntry = [ordered]@{
        session_id = $sessionId
        ts         = $tsMs
        data       = $data
    } | ConvertTo-Json -Compress -Depth 10
    Add-Content -Path (Join-Path $logDir "$sessionId.jsonl") -Value $logEntry -Encoding UTF8
} catch {
    # Logging is best-effort; never break the statusline display
}