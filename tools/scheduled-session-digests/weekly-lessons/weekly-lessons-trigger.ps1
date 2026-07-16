# weekly-lessons-trigger.ps1
#
# Cron entry point for the weekly lessons harvest, run by Windows Task
# Scheduler every Sunday at 02:00.
#
# Thin consumer of weekly-lessons-prepare.ps1 (the shared scan/collect logic,
# also used by the interactive skill):
#   1. Runs the prepare script, which collects the per-session lessons written
#      by daily-lessons since the last harvest into input.md plus manifest.json
#      under .claude\scheduled-session-digests\weekly-lessons\.
#   2. Substitutes the input/master paths into the prompt template
#      (weekly-lessons.md) and runs `claude --print`. The prompt instructs
#      Claude to distil project-generic lessons into the master file.
#   3. Advances the cursor file only after Claude exits successfully, so a
#      crash retries the same files on the next run.
#   4. Removes the staging dir and runs git-sync once.
#
# Task Scheduler setup (done by install.ps1, or manually):
#   Trigger : Weekly, Sunday, 02:00
#   Action  : powershell.exe -NonInteractive -File "<scripts>\weekly-lessons-trigger.ps1"

param(
    [switch]$FullScan
)

$ErrorActionPreference = "Stop"

$Tag     = "[weekly-lessons]"
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
$LogFile = Join-Path $LogDir ("{0}_weekly-lessons-trigger.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# ---------------------------------------------------------------------------
# Guards: everything this trigger needs is installed alongside it
# ---------------------------------------------------------------------------
$Prepare    = Join-Path $PSScriptRoot "weekly-lessons-prepare.ps1"
$PromptFile = Join-Path $PSScriptRoot "weekly-lessons.md"
$GitSync    = Join-Path $PSScriptRoot "git-sync.ps1"
$StagingDir = Join-Path $MetaDir ".claude\scheduled-session-digests\weekly-lessons"
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
    & $Prepare -FullScan
} else {
    & $Prepare
}
if ($LASTEXITCODE -ne 0) {
    Log "Prepare step failed (exit $LASTEXITCODE) - aborting."
    exit 1
}

$doc = Get-Content $Manifest -Raw | ConvertFrom-Json

if ($doc.files -eq 0) {
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Log "Nothing to harvest."
    exit 0
}

# ---------------------------------------------------------------------------
# Run Claude for analysis and master-file update
# ---------------------------------------------------------------------------
# The dedup/generalisation judgement is the hardest step and pollutes the
# permanent master file if done poorly, hence opus at high effort.
$prompt = (Get-Content $PromptFile -Raw).Replace('{{INPUT_FILE}}', $doc.input).Replace('{{MASTER_FILE}}', $doc.master)

try {
    Set-Location $MetaDir
    claude --model opus --effort high --print $prompt

    # Advance the cursor only after Claude exits successfully, so a crash
    # retries the same files next run.
    Set-Content $doc.cursor $doc.cursorEpoch -Encoding ASCII
    Log "Cursor advanced to epoch $($doc.cursorEpoch)."
} finally {
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

& $GitSync -Label "weekly-lessons"

Log "Done. Check $($doc.master) for updates."
