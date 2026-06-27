# Combined install/uninstall for the settings.json sync task.
# Run as Administrator.
# Usage:
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir>                 # install (default), 15-min interval
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir> -IntervalMinutes 30
#   .\settings-sync-setup.ps1 -Action uninstall
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # The two folders whose settings.json to keep in sync (required on install).
    [string]$FolderA,
    [string]$FolderB,

    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15
)

$vbsPath = Join-Path $PSScriptRoot "settings-sync-hidden.vbs"

$taskFolder = "\ClaudeAutomation\"
$taskName   = "SyncClaudeSettings"

# This tool syncs settings.json specifically; only the containing folders are configurable.
$fileName = "settings.json"

function Install-SyncTask {
    if (-not $FolderA -or -not $FolderB) {
        throw "Install requires -FolderA and -FolderB (the two folders whose $fileName to keep in sync)."
    }
    foreach ($f in @($FolderA, $FolderB)) {
        if (-not (Test-Path -PathType Container $f)) { throw "Folder not found: $f" }
    }
    $fileA = Join-Path (Resolve-Path $FolderA).Path $fileName
    $fileB = Join-Path (Resolve-Path $FolderB).Path $fileName

    # ---- CREATE HIDDEN VBS LAUNCHER ----
    # The two file paths are resolved at install time and embedded directly.
    $vbsContent = @"
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\settings-sync.ps1"
fileA = "$fileA"
fileB = "$fileB"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """"
shell.Run cmd, 0, False
"@
    Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII

    # ---- ACTION ----
    $action = New-ScheduledTaskAction `
        -Execute "wscript.exe" `
        -Argument "`"$vbsPath`""

    # ---- TRIGGER: every $IntervalMinutes minutes, every day, forever ----
    # Daily anchor re-arms each day (so it never "expires"); attach the repetition
    # that spans the day. StartWhenAvailable + WakeToRun ensure missed runs fire
    # as soon as the machine is awake again.
    $trigger = New-ScheduledTaskTrigger -Daily -At "12:00am"
    $repeatPattern = New-ScheduledTaskTrigger `
        -Once -At "12:00am" `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)
    $trigger.Repetition = $repeatPattern.Repetition

    # ---- SETTINGS ----
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable `
        -WakeToRun

    # ---- REGISTER TASK ----
    Register-ScheduledTask `
        -TaskName   $taskName `
        -TaskPath   $taskFolder `
        -Action     $action `
        -Trigger    $trigger `
        -Settings   $settings `
        -Force

    Write-Host "Task '$taskName' registered successfully (every $IntervalMinutes minute(s))."
    Write-Host "Syncing: $fileA  <->  $fileB"
}

function Uninstall-SyncTask {
    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -Confirm:$false
        Write-Host "Task '$taskName' unregistered."
    } else {
        Write-Host "Task '$taskName' not found — skipped."
    }

    if (Test-Path $vbsPath) {
        Remove-Item -Force $vbsPath
        Write-Host "Removed hidden launcher $vbsPath"
    } else {
        Write-Host "Hidden launcher not found at $vbsPath — skipped."
    }
}

switch ($Action) {
    'install'   { Install-SyncTask }
    'uninstall' { Uninstall-SyncTask }
}
