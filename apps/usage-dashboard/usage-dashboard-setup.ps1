# Combined install/uninstall for the usage dashboard server task.
# Registers a Windows Task Scheduler task that starts usage-dashboard.py
# at logon and on resume from sleep/hibernate. Run as the current user (no elevation required).
# Usage:
#   .\usage-dashboard-setup.ps1                       # install (default)
#   .\usage-dashboard-setup.ps1 -Action install
#   .\usage-dashboard-setup.ps1 -Action uninstall
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install'
)

$taskFolder = "\ClaudeAutomation"
$taskName   = "StartStatuslineServer"
$wrapperPath = Join-Path $PSScriptRoot "usage-dashboard-start-once.ps1"

function Install-StatuslineServerTask {
    # Ensure the task folder exists
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    try { $svc.GetFolder($taskFolder) | Out-Null }
    catch { $svc.GetFolder((Split-Path $taskFolder)).CreateFolder((Split-Path $taskFolder -Leaf)) | Out-Null }

    # The wrapper checks if the server is already running before launching,
    # making it safe to call from both the logon and wake triggers.
    $action   = New-ScheduledTaskAction `
        -Execute          "powershell.exe" `
        -Argument         "-NonInteractive -WindowStyle Hidden -File `"$wrapperPath`"" `
        -WorkingDirectory $PSScriptRoot

    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName    $taskName `
        -TaskPath    $taskFolder `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -RunLevel    Limited `
        -Description "Starts the Claude Code statusline dashboard server at logon and on resume from sleep/hibernate" `
        -Force

    # Add an event trigger for resume from sleep/hibernate (Event ID 1 from Power-Troubleshooter).
    # Standard cmdlets don't support event triggers, so use the COM API directly.
    $svc.Connect()
    $folder  = $svc.GetFolder($taskFolder)
    $taskObj = $folder.GetTask($taskName)
    $taskDef = $taskObj.Definition

    # TASK_TRIGGER_EVENT = 0
    $evtTrigger = $taskDef.Triggers.Create(0)
    $evtTrigger.Enabled      = $true
    $evtTrigger.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]</Select></Query></QueryList>'

    # TASK_UPDATE = 4, TASK_LOGON_INTERACTIVE_TOKEN = 3
    $folder.RegisterTaskDefinition($taskName, $taskDef, 4, $null, $null, 3) | Out-Null

    Write-Host "Task registered: $taskFolder\$taskName"
    Write-Host "Triggers:  at logon + on resume from sleep/hibernate"
    Write-Host "Wrapper:   $wrapperPath"
}

function Uninstall-StatuslineServerTask {
    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -Confirm:$false
        Write-Host "Task '$taskName' unregistered."
    } else {
        Write-Host "Task '$taskName' not found — skipped."
    }
}

switch ($Action) {
    'install'   { Install-StatuslineServerTask }
    'uninstall' { Uninstall-StatuslineServerTask }
}
