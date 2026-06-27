# Combined install/uninstall for the settings.json sync task.
# Run as Administrator.
# Usage:
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir>                 # install (default), 15-min interval
#   .\settings-sync-setup.ps1 -FolderA <dir> -FolderB <dir> -IntervalMinutes 30
#   .\settings-sync-setup.ps1 -Action uninstall -FolderA <dir> -FolderB <dir>
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # The two folders whose settings.json to keep in sync (required for both actions).
    [string]$FolderA,
    [string]$FolderB,

    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15
)

# This tool syncs settings.json specifically; only the containing folders are configurable.
$fileName = "settings.json"

# Task folder mirrors this tool's folder name, so every install of this tool is grouped
# under one Task Scheduler folder, kept separate from other sync tools' tasks.
$toolName   = Split-Path -Leaf $PSScriptRoot
$taskFolder = "\$toolName\"

function Get-SyncIdentity {
    # Map the folder pair to a stable identity (task name + launcher path) derived from
    # the input args, so different pairs install as independent parallel tasks and
    # install/uninstall always agree. Order-independent: (A,B) and (B,A) match.
    if (-not $FolderA -or -not $FolderB) {
        throw "-FolderA and -FolderB are required (the two folders whose $fileName to keep in sync)."
    }
    $pair  = @(
        [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($FolderA), $fileName)
        [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($FolderB), $fileName)
    ) | Sort-Object
    $key   = ($pair -join '|').ToLowerInvariant()
    $bytes = [System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))
    $short = ([BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 8).ToLower()
    $leaf  = { param($p) (Split-Path -Leaf (Split-Path -Parent $p)) -replace '[^A-Za-z0-9]', '' }
    $slug  = "$(& $leaf $pair[0])-$(& $leaf $pair[1])"
    [pscustomobject]@{
        FileA    = $pair[0]
        FileB    = $pair[1]
        TaskName = "$slug-$short"
        VbsPath  = Join-Path $PSScriptRoot "$toolName-$short-hidden.vbs"
    }
}

function Install-SyncTask {
    $id = Get-SyncIdentity
    foreach ($f in @($FolderA, $FolderB)) {
        if (-not (Test-Path -PathType Container $f)) { throw "Folder not found: $f" }
    }
    $fileA = $id.FileA
    $fileB = $id.FileB

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
    Set-Content -Path $id.VbsPath -Value $vbsContent -Encoding ASCII

    # ---- ACTION ----
    $action = New-ScheduledTaskAction `
        -Execute "wscript.exe" `
        -Argument "`"$($id.VbsPath)`""

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
        -TaskName   $id.TaskName `
        -TaskPath   $taskFolder `
        -Action     $action `
        -Trigger    $trigger `
        -Settings   $settings `
        -Force

    Write-Host "Task '$taskFolder$($id.TaskName)' registered successfully (every $IntervalMinutes minute(s))."
    Write-Host "Syncing: $fileA  <->  $fileB"
}

function Uninstall-SyncTask {
    $id = Get-SyncIdentity
    $existing = Get-ScheduledTask -TaskName $id.TaskName -TaskPath $taskFolder -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $id.TaskName -TaskPath $taskFolder -Confirm:$false
        Write-Host "Task '$($id.TaskName)' unregistered."
    } else {
        Write-Host "Task '$($id.TaskName)' not found — skipped."
    }

    if (Test-Path $id.VbsPath) {
        Remove-Item -Force $id.VbsPath
        Write-Host "Removed hidden launcher $($id.VbsPath)"
    } else {
        Write-Host "Hidden launcher not found at $($id.VbsPath) — skipped."
    }
}

switch ($Action) {
    'install'   { Install-SyncTask }
    'uninstall' { Uninstall-SyncTask }
}
