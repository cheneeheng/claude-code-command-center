# Generic install/uninstall for a file-sync task. Run as Administrator.
#
# Normally invoked through a thin wrapper that fixes -FileName/-Strategy
# (claude-md-sync-setup.ps1, settings-sync-setup.ps1). Call directly to sync any file:
#   .\sync-setup.ps1 -FileName CLAUDE.md -Strategy raw -FolderA <dir> -FolderB <dir>
#   .\sync-setup.ps1 -FileName settings.json -Strategy json-merge -ExcludePaths "statusLine.command" -FolderA <dir> -FolderB <dir>
#   .\sync-setup.ps1 -Action uninstall -FileName CLAUDE.md -FolderA <dir> -FolderB <dir>
param(
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    # The file name to keep in sync (e.g. CLAUDE.md, settings.json).
    [Parameter(Mandatory)]
    [string]$FileName,

    # The two folders that each contain $FileName (required for both actions).
    [string]$FolderA,
    [string]$FolderB,

    [ValidateSet('raw', 'json-merge')]
    [string]$Strategy = 'raw',

    # Comma-separated dot-notation key paths to preserve in the destination (json-merge only).
    [string]$ExcludePaths = '',

    [ValidateRange(1, 1439)]
    [int]$IntervalMinutes = 15
)

# Task folder mirrors this tool's folder name (\file-sync\), so every install of this
# tool is grouped under one Task Scheduler folder, separate from other tools' tasks.
$toolName   = Split-Path -Leaf $PSScriptRoot
$taskFolder = "\$toolName\"

function Get-SyncIdentity {
    # Map the (file, folder pair) to a stable identity (task name + launcher path) derived
    # from the input args, so different files/pairs install as independent parallel tasks and
    # install/uninstall always agree. Order-independent: (A,B) and (B,A) match.
    if (-not $FolderA -or -not $FolderB) {
        throw "-FolderA and -FolderB are required (the two folders whose $FileName to keep in sync)."
    }
    $pair  = @(
        [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($FolderA), $FileName)
        [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($FolderB), $FileName)
    ) | Sort-Object
    $key   = ($pair -join '|').ToLowerInvariant()
    $bytes = [System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))
    $short = ([BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 8).ToLower()
    $leaf  = { param($p) (Split-Path -Leaf (Split-Path -Parent $p)) -replace '[^A-Za-z0-9]', '' }
    # File stem in the slug keeps tasks legible when two files share one folder pair
    # (e.g. CLAUDE.md and settings.json both in .claude <-> .claude_mirror).
    $stem  = [System.IO.Path]::GetFileNameWithoutExtension($FileName) -replace '[^A-Za-z0-9]', ''
    $slug  = "$stem-$(& $leaf $pair[0])-$(& $leaf $pair[1])"
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
    # The two file paths, strategy and excludes are resolved at install time and embedded.
    $vbsContent = @"
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\sync-engine.ps1"
fileA = "$fileA"
fileB = "$fileB"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """ -Strategy $Strategy -ExcludePaths """ & "$ExcludePaths" & """"
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
    Write-Host "Syncing ($Strategy): $fileA  <->  $fileB"
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
