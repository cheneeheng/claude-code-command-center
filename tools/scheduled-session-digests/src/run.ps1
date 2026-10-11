#Requires -Version 7.4
# run.ps1: the only consumer of the pipeline. Takes the lock, works out the
# scan cutoff, calls prepare, sends each staged session to claude once, and
# hands the answers to finish. The meta repo is the one this copy lives in.
#
# Cross-reference: src/run.sh is the Bash twin.

param(
    [ValidateSet('daily')][string]$Job = 'daily',
    [switch]$All,
    [string]$Since,
    [switch]$ArchiveOnly,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Scheduled
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Scheduled) { $Yes = $true }
[Console]::OutputEncoding = $script:Utf8
$OutputEncoding = $script:Utf8
$prepare = Join-Path $PSScriptRoot 'prepare.ps1'

Enter-Lock
$exitCode = 0
try {
    $started = Get-NowEpoch

    # Cutoff: -All is 0, -Since is that local date's midnight, otherwise the
    # stored cursor, or now - firstRunDays when there is none.
    $cursorFile = Join-Path $SlState 'daily.cursor'
    $stored = if (Test-Path -LiteralPath $cursorFile) { [long](Get-Content -Raw $cursorFile).Trim() } else { $null }
    $cutoff = if ($All) { 0 }
        elseif ($Since) { [DateTimeOffset]::new([DateTime]::ParseExact($Since, 'yyyy-MM-dd', $null)).ToUnixTimeSeconds() }
        elseif ($null -ne $stored) { $stored }
        else { (Get-NowEpoch) - [long]$SlConfig.firstRunDays * 86400 }

    if ($ArchiveOnly) { & $prepare -Cutoff $cutoff -Mode archive; return }   # never touches a cursor
    if ($DryRun) { & $prepare -Cutoff $cutoff -Mode dry; return }            # writes nothing at all
    if (-not $Yes) {
        & $prepare -Cutoff $cutoff -Mode dry
        if ([Console]::IsInputRedirected) { Write-Say 'Not confirmed (no terminal). Re-run with -Yes to proceed.'; return }
        if ((Read-Host 'Proceed? [y/N]') -notmatch '^[Yy]$') { Write-Say 'Nothing done.'; return }
    }

    # A real run with no cursor writes its own cutoff first, so a failing first
    # run never lets the window slide. writeCursor: only when this run's cutoff
    # is at or before the stored cursor, so no unscanned range is ever skipped.
    if ($null -eq $stored) { Write-Utf8 $cursorFile "$cutoff`n"; $stored = $cutoff }
    $write = $cutoff -le $stored

    $now = Get-Date
    $logDir = Join-Path $SlMeta ('logs/{0:yyyy}/{0:MM}' -f $now)
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:SlLog = Join-Path $logDir ('{0:yyyyMMdd_HHmmss}_session-lessons-daily.log' -f $now)
    $cap = if ($Scheduled) { [int]$SlConfig.maxSessionsPerRun } else { 0 }

    & $prepare -Cutoff $cutoff -Mode stage -Cap $cap -WriteCursor:$write -Log $script:SlLog

    $manifestPath = Join-Path $SlStaging 'daily/manifest.json'
    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
    $claude = $SlInstall.claudePath
    $noTools = @($SlInstall.claudeNoToolsArgs)
    $model = $SlConfig.models.daily.model; $effort = $SlConfig.models.daily.effort
    $errorText = ''

    if (-not (Test-Path -LiteralPath $claude) -and -not (Get-Command $claude -ErrorAction SilentlyContinue)) {
        $errorText = "claude not found at $claude"
    } else {
        $frame = Get-Content -Raw (Join-Path $PSScriptRoot 'prompts/daily-frame.md')
        $total = $manifest.jobs.Count; $i = 0
        Push-Location -LiteralPath $SlMeta
        try {
            foreach ($j in $manifest.jobs) {
                $i++
                $parts = ($j.needed | ForEach-Object { "<<<extraction:$_>>>" }) -join "`n"
                $sections = ($j.needed | ForEach-Object {
                    "`n`n" + (Get-Content -Raw (Join-Path $PSScriptRoot "prompts/$($SlConfig.extractions.$_.prompt)")).TrimEnd("`n")
                }) -join ''
                $prompt = $frame.TrimEnd("`n").Replace('{{PARTS}}', $parts) + $sections
                $errFile = Join-Path $SlStaging "daily/out/$($j.uuid).err"
                $answer = Get-Content -Raw -LiteralPath (Join-Path $SlMeta $j.input) |
                    & $claude --print --model $model --effort $effort @noTools $prompt 2> $errFile
                $code = $LASTEXITCODE
                Write-Utf8 (Join-Path $SlMeta $j.pending) ((@($answer) -join "`n") + "`n")
                if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
                    [IO.File]::AppendAllText($script:SlLog, [IO.File]::ReadAllText($errFile), $script:Utf8)
                }
                $j.exit = $code
                Write-Utf8 $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")
                if ($code -ne 0) {
                    Write-Say "[$i/$total] $($j.date) $($j.uuid.Substring(0,8)): claude exited $code, stopping."
                    $first = if (Test-Path $errFile) { Get-Content -LiteralPath $errFile | Where-Object { $_ -match '\S' } | Select-Object -First 1 } else { $null }
                    $errorText = "claude exited ${code}: $first"
                    break
                }
                Write-Say "[$i/$total] $($j.date) $($j.uuid.Substring(0,8)): answered"
            }
        } finally { Pop-Location }
    }

    $trigger = if ($Scheduled) { 'scheduled' } else { 'manual' }
    & (Join-Path $PSScriptRoot 'finish.ps1') -Started $started -Trigger $trigger -ErrorText $errorText -Log $script:SlLog
    if ($errorText) { $exitCode = 1 }
} finally {
    Exit-Lock
}
exit $exitCode
