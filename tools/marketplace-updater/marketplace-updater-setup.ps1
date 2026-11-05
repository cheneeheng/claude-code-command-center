# marketplace-updater-setup.ps1 - install / uninstall the marketplace-updater task
#
# Install copies marketplace-updater.ps1 into <InstallDir>, writes <InstallDir>\config.json,
# and registers \ClaudeAutomation\marketplace-updater\marketplace-updater, which runs the
# copy every -IntervalMinutes. Uninstall removes the task and <InstallDir>. <InstallDir>
# defaults to ~\.claude-command-center\marketplace-updater. Both also remove a 0.1.x install
# from %LOCALAPPDATA%\claude-automation\marketplace-updater, keeping its run.log.
#
# The marketplaces and repos are re-read from config.json on every run, so editing that file
# needs no reinstall. Changing the interval does: re-run install with the new -IntervalMinutes.
#
# Examples:
#   .\marketplace-updater-setup.ps1 -Marketplaces my-market -Repos C:\p\a,C:\p\b
#   .\marketplace-updater-setup.ps1 -Marketplaces my-market -Repos C:\p\a -IntervalMinutes 60
#   .\marketplace-updater-setup.ps1 -Action uninstall

param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # Marketplace names as shown by `claude plugin marketplace list`.
    [string[]]$Marketplaces,

    # Repo folders whose local/project-scope plugins get updated.
    [string[]]$Repos,

    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 360,

    [string]$InstallDir = (Join-Path $HOME '.claude-command-center\marketplace-updater')
)

$ErrorActionPreference = 'Stop'
$TaskName   = 'marketplace-updater'
$TaskFolder = "\ClaudeAutomation\$TaskName\"

# Where versions up to 0.1.x installed.
$OldDir = Join-Path $env:LOCALAPPDATA 'claude-automation\marketplace-updater'

# Keep the old run.log unless the new dir has one, then delete the old dir. A run in
# progress can hold run.log open, so a failure warns instead of failing the install.
function Remove-OldInstall {
    if (-not (Test-Path $OldDir) -or $OldDir -eq $InstallDir) { return }
    try {
        $oldLog = Join-Path $OldDir 'run.log'
        $newLog = Join-Path $InstallDir 'run.log'
        if ((Test-Path $oldLog) -and (Test-Path $InstallDir) -and -not (Test-Path $newLog)) {
            Move-Item $oldLog $newLog
            Write-Host "Moved $oldLog to $newLog"
        }
        Remove-Item $OldDir -Recurse -Force
        Write-Host "Removed the old install dir $OldDir"
    } catch {
        Write-Warning "Could not remove the old install dir ${OldDir}: $($_.Exception.Message). Delete it by hand."
    }
}

if ($Action -eq 'uninstall') {
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Removed task $TaskFolder$TaskName"
    } else {
        Write-Host "Task $TaskFolder$TaskName not registered, skipped."
    }
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Write-Host "Removed $InstallDir" }
    Remove-OldInstall
    return
}

$Marketplaces = @($Marketplaces | Where-Object { $_ })
$Repos = @($Repos | Where-Object { $_ })
if (-not $Marketplaces -or -not $Repos) { throw '-Marketplaces and -Repos are both required.' }
foreach ($r in $Repos) { if (-not (Test-Path -PathType Container $r)) { throw "Repo folder not found: $r" } }

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$worker = Join-Path $InstallDir 'marketplace-updater.ps1'
Copy-Item (Join-Path $PSScriptRoot 'marketplace-updater.ps1') $worker -Force
[pscustomobject]@{ marketplaces = $Marketplaces; repos = $Repos } |
    ConvertTo-Json | Set-Content (Join-Path $InstallDir 'config.json') -Encoding UTF8

# conhost --headless gives pwsh a console that is never shown, so no window flashes on each run.
$pwsh   = (Get-Command pwsh).Source
$taskAction = New-ScheduledTaskAction -Execute 'conhost.exe' `
    -Argument "--headless `"$pwsh`" -NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$worker`""

# Daily anchor with an in-day repetition, so the trigger never expires.
$trigger = New-ScheduledTaskTrigger -Daily -At '12:00am'
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At '12:00am' `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)).Repetition

$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Action $taskAction `
    -Trigger $trigger -Settings $settings -Force | Out-Null

# Only now that the task runs the new worker, so a failed registration leaves the old one working.
Remove-OldInstall

Write-Host "Registered $TaskFolder$TaskName (every $IntervalMinutes minute(s))."
Write-Host "Config : $(Join-Path $InstallDir 'config.json')"
Write-Host "Log    : $(Join-Path $InstallDir 'run.log')"
Write-Host "Try it : & '$worker' -DryRun"
