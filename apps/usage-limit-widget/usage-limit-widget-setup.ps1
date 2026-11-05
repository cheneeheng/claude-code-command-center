# Install / uninstall the usage-limit-widget logon task (Windows).
#
# install:   registers \ClaudeAutomation\usage-limit-widget\widget, which starts the widget
#            with pythonw at logon and restarts it every hour after, then starts it now.
# uninstall: stops and removes the task.
#
# Usage:
#   .\usage-limit-widget-setup.ps1                     # install (default)
#   .\usage-limit-widget-setup.ps1 -Action uninstall
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install'
)

$ErrorActionPreference = 'Stop'

$AppDir     = $PSScriptRoot
$Widget     = Join-Path $AppDir 'claude_usage_widget.pyw'
# Task folder nests the app's folder name under the shared \ClaudeAutomation\ root.
$TaskFolder = "\ClaudeAutomation\$(Split-Path -Leaf $AppDir)\"
$TaskName   = 'widget'

$existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue

if ($Action -eq 'uninstall') {
    if ($existing) {
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false
        Write-Host "Stopped and removed task $TaskFolder$TaskName"
    } else {
        Write-Host "Task $TaskFolder$TaskName not found, skipped."
    }
    return
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "'uv' is not on PATH. Install it from https://docs.astral.sh/uv/"
}
# The widget is stdlib-only, so it runs on a base interpreter uv picks for this project.
# --system skips the git-ignored .venv, which can be deleted and whose pythonw.exe is a
# redirector that starts a second process. pythonw.exe runs without a console window.
Push-Location $AppDir
try { $Python = uv python find --system } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw "uv python find failed (exit $LASTEXITCODE)" }
$Pythonw = Join-Path (Split-Path $Python) 'pythonw.exe'
if (-not (Test-Path $Pythonw)) { throw "Expected $Pythonw next to $Python, not found." }

$TaskAction  = New-ScheduledTaskAction -Execute $Pythonw -Argument "`"$Widget`"" -WorkingDirectory $AppDir
$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# -AtLogOn takes no repetition parameters, so borrow the repetition from a -Once trigger.
# No duration means it repeats for as long as the user stays logged on.
$TaskTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Hours 1)).Repetition
# A zero time limit means no limit: the hourly restart, not a timeout, ends each run.
# Keep running on battery, since the defaults would stop the widget on a laptop.
$TaskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
# StopExisting (3) makes each hourly start replace the running widget. The cmdlet's
# -MultipleInstances parameter does not offer it, so set the CIM property directly.
$TaskSettings.CimInstanceProperties.Item('MultipleInstances').Value = 3

if ($existing) { Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder }
Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder `
    -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings `
    -RunLevel Limited -Force `
    -Description 'Claude usage-limit widget at the top edge of the screen, restarted hourly' | Out-Null
Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder
Write-Host "Registered and started $TaskFolder$TaskName (at logon, restarted hourly)"
Write-Host "Interpreter: $Pythonw"
