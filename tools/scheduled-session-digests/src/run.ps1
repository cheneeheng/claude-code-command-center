#Requires -Version 7.4
# run.ps1: the only consumer of the pipeline. Takes the lock, works out the
# scan cutoff, calls prepare, sends each staged session (daily) or batch
# (weekly) to claude once, and hands the answers to finish. The meta repo is
# the one this installed copy lives in.
#
# Cross-reference: src/run.sh is the Bash twin.

param(
    [ValidateSet('', 'daily', 'weekly')][string]$Job = '',
    [switch]$All,
    [string]$Since,
    [switch]$ArchiveOnly,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Scheduled
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons

# The scheduled entry calls -Scheduled with no job: run each due job in turn,
# daily first, each as its own run (and so its own lock). Not due: exit quietly.
if ($Scheduled) {
    if (-not $Job) {
        $rc = 0
        foreach ($j in 'daily', 'weekly') {
            if (Test-JobDue $j) { & $PSCommandPath -Scheduled -Job $j; if ($LASTEXITCODE -ne 0) { $rc = 1 } }
        }
        exit $rc
    }
    if (-not (Test-JobDue $Job)) { exit 0 }
    $Yes = $true
}
if (-not $Job) { $Job = 'daily' }
[Console]::OutputEncoding = $script:Utf8
$OutputEncoding = $script:Utf8
$trigger = if ($Scheduled) { 'scheduled' } else { 'manual' }

function Get-StoredCursor([string]$Path) { if (Test-Path -LiteralPath $Path) { [long](Get-Content -Raw $Path).Trim() } else { $null } }

# Cutoff: -All is 0, -Since is that local date's midnight, otherwise the stored
# cursor, or now - firstRunDays when there is none.
function Get-Cutoff($Stored) {
    if ($All) { return 0 }
    if ($Since) { return [DateTimeOffset]::new([DateTime]::ParseExact($Since, 'yyyy-MM-dd', $null)).ToUnixTimeSeconds() }
    if ($null -ne $Stored) { return $Stored }
    (Get-NowEpoch) - [long]$SlConfig.firstRunDays * 86400
}
# Returns $true to go on; prints why not otherwise.
function Confirm-Run {
    if ([Console]::IsInputRedirected) { Write-Say 'Not confirmed (no terminal). Re-run with -Yes to proceed.'; return $false }
    if ((Read-Host 'Proceed? [y/N]') -notmatch '^[Yy]$') { Write-Say 'Nothing done.'; return $false }
    $true
}
function Open-Log([string]$Name) {
    $now = Get-Date
    $logDir = Join-Path $SlMeta ('logs/{0:yyyy}/{0:MM}' -f $now)
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:SlLog = Join-Path $logDir ("{0:yyyyMMdd_HHmmss}_session-lessons-$Name.log" -f $now)
}
function Test-Claude([string]$Path) { (Test-Path -LiteralPath $Path) -or [bool](Get-Command $Path -ErrorAction SilentlyContinue) }
# Pipes a file into claude with a prompt; writes stdout to $Out, returns the exit code.
function Invoke-Claude([string]$In, [string]$Out, [string]$Prompt, [string]$Model, [string]$Effort) {
    $err = "$Out.err"
    $answer = Get-Content -Raw -LiteralPath $In |
        & $SlInstall.claudePath --print --model $Model --effort $Effort @(@($SlInstall.claudeNoToolsArgs)) $Prompt 2> $err
    $code = $LASTEXITCODE
    Write-Utf8 $Out ((@($answer) -join "`n") + "`n")
    if ((Test-Path $err) -and (Get-Item $err).Length -gt 0) {
        [IO.File]::AppendAllText($script:SlLog, [IO.File]::ReadAllText($err), $script:Utf8)
    }
    $code
}
function Get-FirstErrorLine([string]$Out) {
    if (Test-Path "$Out.err") { Get-Content -LiteralPath "$Out.err" | Where-Object { $_ -match '\S' } | Select-Object -First 1 }
}

Enter-Lock
$exitCode = 0
try {
    $started = Get-NowEpoch

    # --- weekly: one merge per extraction with a weekly entry ------------------
    if ($Job -eq 'weekly') {
        $exts = @($SlConfig.extractions.PSObject.Properties | Where-Object { $_.Value.enabled -and $_.Value.weekly } | ForEach-Object Name)
        $prepW = Join-Path $PSScriptRoot 'prepare-weekly.ps1'
        $finW = Join-Path $PSScriptRoot 'finish-weekly.ps1'
        $sto = @{}; $cut = @{}
        foreach ($e in $exts) { $sto[$e] = Get-StoredCursor (Join-Path $SlState "weekly-$e.cursor"); $cut[$e] = Get-Cutoff $sto[$e] }
        if ($DryRun -or -not $Yes) {
            foreach ($e in $exts) { & $prepW -Ext $e -Cutoff $cut[$e] -Mode dry }
            if ($DryRun -or -not (Confirm-Run)) { return }
        }
        Open-Log 'weekly'
        foreach ($e in $exts) {
            if ($null -eq $sto[$e]) { Write-Utf8 (Join-Path $SlState "weekly-$e.cursor") "$($cut[$e])`n"; $sto[$e] = $cut[$e] }
            & $prepW -Ext $e -Cutoff $cut[$e] -Mode stage -WriteCursor:($cut[$e] -le $sto[$e]) -Log $script:SlLog
        }
        $errorText = ''
        if (-not (Test-Claude $SlInstall.claudePath)) {
            $errorText = "claude not found at $($SlInstall.claudePath)"
        } else {
            Push-Location -LiteralPath $SlMeta
            try {
                :exts foreach ($e in $exts) {
                    $mp = Join-Path $SlStaging "weekly-$e/manifest.json"
                    $prompt = (Get-Content -Raw (Join-Path $PSScriptRoot "prompts/$($SlConfig.extractions.$e.weekly.prompt)")).TrimEnd("`n")
                    $count = @((Get-Content -Raw $mp | ConvertFrom-Json -AsHashtable).batches).Count
                    for ($k = 0; $k -lt $count; $k++) {
                        $m = Get-Content -Raw $mp | ConvertFrom-Json -AsHashtable
                        $b = $m.batches[$k]
                        $out = Join-Path $SlMeta $b.pending
                        $code = Invoke-Claude (Join-Path $SlMeta $b.input) $out $prompt $SlConfig.models.weekly.model $SlConfig.models.weekly.effort
                        $b.exit = $code
                        Write-Utf8 $mp (($m | ConvertTo-Json -Depth 6) + "`n")
                        if ($code -ne 0) {
                            Write-Say "Batch $($k + 1): claude exited $code, stopping."
                            $errorText = "claude exited ${code}: $(Get-FirstErrorLine $out)"
                            break exts
                        }
                        & $finW -Ext $e -Batch $k -Log $script:SlLog
                        if ($LASTEXITCODE -ne 0) { break exts }
                    }
                }
            } finally { Pop-Location }
        }
        # finish-weekly exits 1 when the run has an error: claude's, or a failed commit.
        & $finW -Close -Started $started -Trigger $trigger -ErrorText $errorText -Log $script:SlLog
        if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
    } else {

    # --- daily -------------------------------------------------------------------
    $prepare = Join-Path $PSScriptRoot 'prepare.ps1'
    $cursorFile = Join-Path $SlState 'daily.cursor'
    $stored = Get-StoredCursor $cursorFile
    $cutoff = Get-Cutoff $stored

    if ($ArchiveOnly) { & $prepare -Cutoff $cutoff -Mode archive; return }   # never touches a cursor
    if ($DryRun) { & $prepare -Cutoff $cutoff -Mode dry; return }            # writes nothing at all
    if (-not $Yes) {
        & $prepare -Cutoff $cutoff -Mode dry
        if (-not (Confirm-Run)) { return }
    }

    # A real run with no cursor writes its own cutoff first, so a failing first
    # run never lets the window slide. writeCursor: only when this run's cutoff
    # is at or before the stored cursor, so no unscanned range is ever skipped.
    if ($null -eq $stored) { Write-Utf8 $cursorFile "$cutoff`n"; $stored = $cutoff }
    $write = $cutoff -le $stored

    Open-Log 'daily'
    $cap = if ($Scheduled) { [int]$SlConfig.maxSessionsPerRun } else { 0 }
    & $prepare -Cutoff $cutoff -Mode stage -Cap $cap -WriteCursor:$write -Log $script:SlLog

    $manifestPath = Join-Path $SlStaging 'daily/manifest.json'
    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json -AsHashtable
    $errorText = ''

    if (-not (Test-Claude $SlInstall.claudePath)) {
        $errorText = "claude not found at $($SlInstall.claudePath)"
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
                $out = Join-Path $SlMeta $j.pending
                $code = Invoke-Claude (Join-Path $SlMeta $j.input) $out $prompt $SlConfig.models.daily.model $SlConfig.models.daily.effort
                $j.exit = $code
                Write-Utf8 $manifestPath (($manifest | ConvertTo-Json -Depth 6) + "`n")
                if ($code -ne 0) {
                    Write-Say "[$i/$total] $($j.date) $($j.uuid.Substring(0,8)): claude exited $code, stopping."
                    $errorText = "claude exited ${code}: $(Get-FirstErrorLine $out)"
                    break
                }
                Write-Say "[$i/$total] $($j.date) $($j.uuid.Substring(0,8)): answered"
            }
        } finally { Pop-Location }
    }

    # finish exits 1 when the run has an error: claude's, or a failed commit.
    & (Join-Path $PSScriptRoot 'finish.ps1') -Started $started -Trigger $trigger -ErrorText $errorText -Log $script:SlLog
    if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
    }
} finally {
    Exit-Lock
}
exit $exitCode
