# daily-digest-trigger.ps1
#
# Cron entry point for one daily digest scheduler, run by Windows Task Scheduler
# (daily-summary at 02:00, daily-lessons at 03:00 - staggered to avoid
# concurrent git-sync commits on the same meta repo).
#
# Thin consumer of daily-digest-prepare.ps1 (the shared scan/stage logic, also
# used by the interactive skill):
#   1. Runs the prepare script, which stages one input file per new chat plus
#      manifest.json under .claude\scheduled-session-digests\<scheduler>\.
#   2. For each staged job, substitutes the job's input/output paths into the
#      scheduler's prompt template (<scheduler>.md) and runs `claude --print`.
#      The prompt instructs Claude to write the digest (or a no-content stub)
#      directly to the output path.
#   3. Advances the cursor file after each verified output, oldest-first, so a
#      crash or failed job retries exactly the unprocessed chats next run.
#   4. Removes the staging dir and runs git-sync once.
#
# Task Scheduler setup (done by install.ps1, or manually):
#   Trigger : Daily, e.g. 02:00
#   Action  : powershell.exe -NonInteractive -File "<scripts>\daily-digest-trigger.ps1" -Scheduler daily-summary

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily-summary', 'daily-lessons')]
    [string]$Scheduler,

    [switch]$FullScan
)

$ErrorActionPreference = "Stop"

# Per-scheduler model choice: summaries are cheap and high-frequency; lessons
# extraction benefits from deeper reasoning.
$Settings = @{
    'daily-summary' = @{ Model = 'haiku';  Effort = 'low' }
    'daily-lessons' = @{ Model = 'sonnet'; Effort = 'medium' }
}[$Scheduler]

$Tag     = "[$Scheduler]"
$LogFile = $null

function Log {
    param([string]$Msg)
    $line = "[{0}] {1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $script:Tag, $Msg
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

$MetaDir = $env:C4_CLAUDE_META_DIR
if (-not $MetaDir) {
    Log "C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogDir = Join-Path $MetaDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("{0}_{1}-trigger.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $Scheduler)

# ---------------------------------------------------------------------------
# Guards: everything this trigger needs is installed alongside it
# ---------------------------------------------------------------------------
$Prepare    = Join-Path $PSScriptRoot "daily-digest-prepare.ps1"
$PromptFile = Join-Path $PSScriptRoot "$Scheduler.md"
$GitSync    = Join-Path $PSScriptRoot "git-sync.ps1"
$StagingDir = Join-Path $MetaDir ".claude\scheduled-session-digests\$Scheduler"
$Manifest   = Join-Path $StagingDir "manifest.json"

foreach ($required in @($Prepare, $PromptFile, $GitSync)) {
    if (-not (Test-Path $required)) {
        Log "Required file not found: $required - run install.ps1 first."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Stage the work
# ---------------------------------------------------------------------------
if ($FullScan) {
    & $Prepare -Scheduler $Scheduler -FullScan
} else {
    & $Prepare -Scheduler $Scheduler
}
if ($LASTEXITCODE -ne 0) {
    Log "Prepare step failed (exit $LASTEXITCODE) - aborting."
    exit 1
}

$doc  = Get-Content $Manifest -Raw | ConvertFrom-Json
$jobs = @($doc.jobs)
$CursorFile = $doc.cursor

if ($jobs.Count -eq 0) {
    # No jobs staged. Recent chats may still have been deliberately skipped
    # (already processed / too short); advancing the cursor past them saves
    # rescanning them every run.
    if ($doc.cursorEpoch -gt 0) { Set-Content $CursorFile $doc.cursorEpoch -Encoding ASCII }
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Log "Nothing to process."
    exit 0
}

# ---------------------------------------------------------------------------
# Process each staged job with claude --print
# ---------------------------------------------------------------------------
$Template  = Get-Content $PromptFile -Raw
$Processed = 0
$AllOk     = $true

Set-Location $MetaDir

try {
    foreach ($job in $jobs) {
        Log "Processing: $($job.uuid) ($($job.date))..."

        $prompt = $Template.Replace('{{INPUT_FILE}}', $job.input).Replace('{{OUTPUT_FILE}}', $job.output)
        claude --model $Settings.Model --effort $Settings.Effort --print $prompt

        if ((Test-Path $job.output) -and (Get-Item $job.output).Length -gt 0) {
            $Processed++
            Log "Written: $($job.output)"
            # Jobs are oldest-first: advance the cursor over this chat only while
            # every earlier job succeeded, so a failed chat is retried next run.
            if ($AllOk) { Set-Content $CursorFile $job.mtime -Encoding ASCII }
        } else {
            $AllOk = $false
            Log "WARNING: no output produced for $($job.uuid) - it will be retried next run."
        }

        Remove-Item $job.input -ErrorAction SilentlyContinue
    }

    # A fully successful run also advances past chats the prepare step skipped.
    if ($AllOk) { Set-Content $CursorFile $doc.cursorEpoch -Encoding ASCII }
} finally {
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if ($Processed -gt 0) {
    & $GitSync -Label $Scheduler
    Log "Done. Processed $Processed chat(s)."
} else {
    Log "No output produced - nothing to commit."
}
