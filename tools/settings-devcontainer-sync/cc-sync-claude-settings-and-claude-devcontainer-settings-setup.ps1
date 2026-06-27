# Combined install/uninstall for the settings.json sync task.
# Run as Administrator.
# Usage:
#   .\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1                              # install (default), 15-min interval
#   .\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -Action install -IntervalMinutes 30
#   .\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -Action uninstall
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15
)

$vbsPath = Join-Path $PSScriptRoot "cc-sync-claude-settings-and-claude-devcontainer-settings-hidden.vbs"

$taskFolder = "\ClaudeAutomation\"
$taskName   = "SyncClaudeSettings"

function Install-SyncTask {
    # ---- CREATE HIDDEN VBS LAUNCHER ----
    $vbsContent = @"
Set shell = CreateObject("WScript.Shell")
home = shell.ExpandEnvironmentStrings("%USERPROFILE%")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\cc-sync-claude-settings-and-claude-devcontainer-settings.ps1"
fileA = home & "\.claude\settings.json"
fileB = home & "\.claude_devcontainer\settings.json"

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
