#Requires -Version 7.4
# lessons.ps1: the session-lessons CLI for Windows. Run it from the clone.
#
#   install   [-MetaDir <p>] [-DailyAt HH:MM] [-WeeklyDay <Day>] [-WeeklyAt HH:MM]
#             [-NoSchedule] [-NoArchive] [-Yes]
#   run       [-MetaDir <p>] [run.ps1 options: -Job, -All, -Since, -DryRun, -Yes, ...]
#   status    [-MetaDir <p>]
#   uninstall [-MetaDir <p>] [-Purge] [-Yes]
#
# -MetaDir defaults to $env:C4_CLAUDE_META_DIR, then ~/claude-meta.
# Cross-reference: lessons.sh is the Linux twin.

param(
    [Parameter(Position = 0)][string]$Command,
    [string]$MetaDir,
    [string]$DailyAt, [string]$WeeklyDay, [string]$WeeklyAt,
    [switch]$NoSchedule, [switch]$NoArchive, [switch]$Yes, [switch]$Purge,
    [string]$Job, [switch]$All, [string]$Since, [switch]$DryRun, [switch]$ArchiveOnly, [switch]$Scheduled
)

$ErrorActionPreference = 'Stop'
$member = $PSScriptRoot
function Stop-Cli([string]$Message) { [Console]::Error.WriteLine("lessons: $Message"); exit 1 }

if (-not $MetaDir) { $MetaDir = if ($env:C4_CLAUDE_META_DIR) { $env:C4_CLAUDE_META_DIR } else { Join-Path $HOME 'claude-meta' } }
$meta = [IO.Path]::GetFullPath($MetaDir)
$h = Join-Path $meta '.claude/session-lessons'
$taskFolder = '\ClaudeAutomation\scheduled-session-digests\'
$id = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($meta))).Substring(0, 8).ToLower()
$taskName = "SessionLessons-$id"

# The helpers come from this clone's src/ (the same version install copies).
# Dot-sourced at script level: inside a function they would vanish on return.
. (Join-Path $member 'src/lib.ps1')

# Points the helpers at this meta repo and loads its config and install record.
function Use-Lib {
    $script:SlMeta = $meta; $script:SlHome = $h; $script:SlState = Join-Path $h 'state'
    $script:SlStaging = Join-Path $h 'staging'
    $cfg = Join-Path $h 'config.json'; $ins = Join-Path $h 'state/install.json'
    if (Test-Path -LiteralPath $cfg) { $script:SlConfig = Get-Content -Raw $cfg | ConvertFrom-Json }
    if (Test-Path -LiteralPath $ins) { $script:SlInstall = Get-Content -Raw $ins | ConvertFrom-Json }
}
function Use-Installed {
    if (-not (Test-Path -LiteralPath (Join-Path $h 'state/install.json'))) {
        Stop-Cli "nothing installed in $meta. Run: pwsh lessons.ps1 install"
    }
    Use-Lib
}
function Assert-NotRunning {
    $lock = Join-Path $h 'state/run.lock'
    if ((Test-Path -LiteralPath $lock) -and (Test-LockLive $lock)) { Stop-Cli 'a run is in progress (state/run.lock). Try again when it ends.' }
}
function Confirm-Change {
    if ($Yes) { return }
    if ([Console]::IsInputRedirected) { Stop-Cli 'not confirmed (no terminal). Re-run with -Yes.' }
    if ((Read-Host 'Proceed? [y/N]') -notmatch '^[Yy]$') { Write-Output 'Nothing changed.'; exit 0 }
}
function Format-Time([long]$Epoch) { (ConvertFrom-Epoch $Epoch).ToString('yyyy-MM-dd HH:mm') }
# The line that loads an enabled weekly "replace" master (decisions' SOUL.md)
# into every session, with forward slashes. Printed, never written:
# ~/.claude/CLAUDE.md is the user's.
function Write-ImportLine([string]$Master) {
    Write-Output 'Add this line to ~/.claude/CLAUDE.md to load your decisions:'
    Write-Output "  @$($meta -replace '\\', '/')/$Master"
}
function Get-ReplaceMasters { @($SlConfig.extractions.PSObject.Properties | Where-Object { $_.Value.enabled -and $_.Value.weekly.mode -eq 'replace' }) }
function Get-OurTask { Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue }
# Adds every key of $Default missing from $User, recursing into objects, so new
# default keys reach existing extractions while the user's own values win (jq's
# `*` in lessons.sh).
function Merge-Default($Default, $User) {
    foreach ($k in $Default.Keys) {
        if (-not $User.Contains($k)) { $User[$k] = $Default[$k] }
        elseif ($User[$k] -is [Collections.IDictionary] -and $Default[$k] -is [Collections.IDictionary]) { Merge-Default $Default[$k] $User[$k] }
    }
}

# ------------------------------------------------------------------------------
function Invoke-Install {
    # The native claude.exe first: a claude.ps1 wrapper earlier on PATH may not
    # forward piped input, and run.ps1 sends the transcript on stdin.
    $claude = (@(Get-Command claude.exe -CommandType Application -All -ErrorAction SilentlyContinue) +
        @(Get-Command claude -ErrorAction SilentlyContinue) | Select-Object -First 1).Source
    if (-not $claude) { Stop-Cli 'claude is not on PATH. Install Claude Code first.' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Cli 'git is not on PATH.' }
    Use-Lib
    Assert-NotRunning

    $scripts = Join-Path $meta '.claude/scripts'
    $changes = [System.Collections.Generic.List[string]]::new(); $keep = [System.Collections.Generic.List[string]]::new()
    $newMeta = -not (Test-Path -LiteralPath $meta)
    $newGit = -not (Test-Path -LiteralPath (Join-Path $meta '.git'))
    if ($newMeta) { $changes.Add('Create the meta repo folder.') }
    if ($newGit) { $changes.Add('Run git init in the meta repo.') }

    # The previous version of this tool, only where it points at this meta repo.
    $legacyFiles = @(foreach ($f in 'daily-digest-prepare.ps1', 'daily-digest-prepare.sh', 'daily-digest-trigger.ps1',
            'daily-digest-trigger.sh', 'weekly-lessons-prepare.ps1', 'weekly-lessons-prepare.sh',
            'weekly-lessons-trigger.ps1', 'weekly-lessons-trigger.sh', 'daily-summary.md', 'daily-lessons.md',
            'weekly-lessons.md', 'git-sync.ps1', 'git-sync.sh', 'VERSION', 'scheduler-config.json') {
        $p = Join-Path $scripts $f; if (Test-Path -LiteralPath $p) { $p } })
    $legacyDirs = @(Get-ChildItem -Path (Join-Path $meta '.claude/skills') -Directory -Filter 'session-digest-*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $oldStaging = Join-Path $meta '.claude/scheduled-session-digests'
    if (Test-Path -LiteralPath $oldStaging) { $legacyDirs += $oldStaging }
    $oldScripts = (Join-Path $meta '.claude\scripts\').ToLower()
    $legacyTasks = @(Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskName -like 'SessionDigest-*' -and ($_.Actions | Where-Object { "$($_.Arguments)".ToLower().Contains($oldScripts) }) })
    if ($legacyFiles.Count) { $changes.Add("Remove $($legacyFiles.Count) old script file(s) from .claude/scripts/ (other files stay).") }
    if ($legacyDirs.Count) { $changes.Add('Remove the old interactive skills and staging folder.') }
    foreach ($t in $legacyTasks) { $changes.Add("Remove the old scheduled task $($t.TaskName).") }
    $oldDaily = Join-Path $meta '.claude/daily-lessons-cursor'; $oldWeekly = Join-Path $meta '.claude/weekly-lessons-cursor'
    if (Test-Path -LiteralPath $oldDaily) { $changes.Add('Carry the old daily-lessons progress marker over.') }
    if (Test-Path -LiteralPath $oldWeekly) { $changes.Add('Carry the old weekly-lessons progress marker over.') }
    $cfgPath = Join-Path $h 'config.json'
    $carry = $null
    $oldCfg = Join-Path $scripts 'scheduler-config.json'
    if ((Test-Path -LiteralPath $oldCfg) -and -not (Test-Path -LiteralPath $cfgPath)) {
        $carry = Get-Content -Raw $oldCfg | ConvertFrom-Json
        $changes.Add('Carry the old schedule and thresholds over.')
    }
    if (Test-Path -LiteralPath (Join-Path $meta '.claude/daily-summary-cursor')) { $keep.Add('.claude/daily-summary-cursor') }
    if (Test-Path -LiteralPath (Join-Path $meta 'daily-summaries')) { $keep.Add('daily-summaries/') }
    if (Test-Path -LiteralPath (Join-Path $meta '.claude/settings.json')) { $keep.Add('.claude/settings.json') }
    if ([Environment]::GetEnvironmentVariable('C4_CLAUDE_META_DIR', 'User')) { $keep.Add('the C4_CLAUDE_META_DIR variable') }

    $changes.Add('Install the scripts into .claude/session-lessons/src/.')
    $changes.Add($(if (Test-Path -LiteralPath $cfgPath) { 'Keep config.json (add any missing extraction or setting).' } else { 'Create .claude/session-lessons/config.json.' }))
    $gi = Join-Path $meta '.gitignore'
    $giHave = if (Test-Path -LiteralPath $gi) { @(Get-Content -LiteralPath $gi) } else { @() }
    $giNew = @('logs/*session-lessons-*', '.claude/session-lessons/state/', '.claude/session-lessons/staging/' | Where-Object { $giHave -cnotcontains $_ })
    if ($giNew.Count) { $changes.Add("Add $($giNew.Count) line(s) to .gitignore.") }
    $addTask = $false
    if (-not $NoSchedule) {
        if (Get-OurTask) { $changes.Add('Keep the existing hourly scheduled task.') }
        else { $addTask = $true; $changes.Add("Add the hourly task $taskName (it runs only what is due).") }
    }
    $roots = if ($env:C4_CLAUDE_DIR) { @($env:C4_CLAUDE_DIR -split [IO.Path]::PathSeparator | Where-Object { $_ }) }
             else { @((Join-Path $HOME '.claude'), (Join-Path $HOME '.claude_devcontainer')) }
    if (-not $NoArchive) {
        $count = 0
        foreach ($r in $roots) {
            $p = Join-Path $r 'projects'
            if (Test-Path -LiteralPath $p) { $count += @(Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.jsonl' | Where-Object { $_.FullName -notmatch '[/\\]subagents[/\\]' }).Count }
        }
        $changes.Add("Archive up to $count session(s) on disk (no claude cost).")
    }

    Write-Output 'Install session lessons into:'
    Write-Output "  $meta"
    foreach ($c in $changes) { Write-Output "  - $c" }
    if ($keep.Count) { Write-Output 'Left as they are:'; foreach ($k in $keep) { Write-Output "  - $k" } }
    Confirm-Change

    # --- apply ---
    New-Item -ItemType Directory -Force -Path (Join-Path $h 'state') | Out-Null
    if ($newGit) { git -C $meta init -q | Out-Null }
    $removed = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $oldDaily) {
        $n = Join-Path $h 'state/daily.cursor'; if (-not (Test-Path -LiteralPath $n)) { Copy-Item -LiteralPath $oldDaily $n }
        Remove-Item -LiteralPath $oldDaily; $removed.Add('.claude/daily-lessons-cursor')
    }
    if (Test-Path -LiteralPath $oldWeekly) {
        $n = Join-Path $h 'state/weekly-lessons.cursor'; if (-not (Test-Path -LiteralPath $n)) { Copy-Item -LiteralPath $oldWeekly $n }
        Remove-Item -LiteralPath $oldWeekly; $removed.Add('.claude/weekly-lessons-cursor')
    }
    foreach ($p in $legacyFiles + $legacyDirs) {
        Remove-Item -Recurse -Force -LiteralPath $p
        $removed.Add(([IO.Path]::GetRelativePath($meta, $p) -replace '\\', '/'))
    }
    foreach ($t in $legacyTasks) {
        Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false
        $removed.Add("task: $($t.TaskPath)$($t.TaskName)")
    }

    $src = Join-Path $h 'src'
    if (Test-Path -LiteralPath $src) { Remove-Item -Recurse -Force -LiteralPath $src }
    Copy-Item -Recurse -LiteralPath (Join-Path $member 'src') $src

    $defaults = Get-Content -Raw (Join-Path $member 'src/config.default.json') | ConvertFrom-Json -AsHashtable
    if (Test-Path -LiteralPath $cfgPath) {
        $cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json -AsHashtable
        if (-not $cfg.extractions) { $cfg.extractions = [ordered]@{} }
        Merge-Default $defaults.extractions $cfg.extractions
    } else {
        $cfg = $defaults
        if ($carry) {
            if ($carry.dailyLessons.scheduleTime) { $cfg.schedule.dailyAt = $carry.dailyLessons.scheduleTime }
            if ($carry.weeklyLessons.scheduleTime) { $cfg.schedule.weeklyAt = $carry.weeklyLessons.scheduleTime }
            if ($carry.weeklyLessons.scheduleDayOfWeek) { $cfg.schedule.weeklyDay = $carry.weeklyLessons.scheduleDayOfWeek }
            if ($null -ne $carry.dailyLessons.minUserTurns) { $cfg.thresholds.minUserTurns = $carry.dailyLessons.minUserTurns }
            if ($null -ne $carry.dailyLessons.minTranscriptChars) { $cfg.thresholds.minTranscriptChars = $carry.dailyLessons.minTranscriptChars }
        }
    }
    if ($DailyAt) { $cfg.schedule.dailyAt = $DailyAt }
    if ($WeeklyDay) { $cfg.schedule.weeklyDay = $WeeklyDay }
    if ($WeeklyAt) { $cfg.schedule.weeklyAt = $WeeklyAt }
    Write-Utf8 $cfgPath (($cfg | ConvertTo-Json -Depth 8) + "`n")

    $insPath = Join-Path $h 'state/install.json'
    $old = if (Test-Path -LiteralPath $insPath) { Get-Content -Raw $insPath | ConvertFrom-Json -AsHashtable } else { @{ installed = @{} } }
    $tasks = @($old.installed.tasks); if ($addTask) { $tasks += "$taskFolder$taskName" }
    $ins = [ordered]@{
        version = $(if (Test-Path (Join-Path $member 'VERSION')) { (Get-Content -Raw (Join-Path $member 'VERSION')).Trim() } else { 'dev' })
        installedAt = $(if ($old.installedAt) { $old.installedAt } else { Get-NowEpoch })
        claudePath = $claude
        claudeNoToolsArgs = @('--tools', '', '--no-session-persistence')
        scanRoots = @($roots)
        # The question queue's gh; none is fine (the queue stays off).
        ghPath = (Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        taskName = "$taskFolder$taskName"
        installed = [ordered]@{
            createdMetaDir = $(if ($null -ne $old.installed.createdMetaDir) { $old.installed.createdMetaDir } else { $newMeta })
            gitInit = $(if ($null -ne $old.installed.gitInit) { $old.installed.gitInit } else { $newGit })
            tasks = @($tasks | Where-Object { $_ } | Select-Object -Unique)
            cronLines = @()
            gitignoreLines = @(@($old.installed.gitignoreLines) + $giNew | Where-Object { $_ } | Select-Object -Unique)
            legacyRemoved = @(@($old.installed.legacyRemoved) + $removed | Where-Object { $_ })
        }
    }
    Write-Utf8 $insPath (($ins | ConvertTo-Json -Depth 6) + "`n")

    if ($giNew.Count) { [IO.File]::AppendAllText($gi, (($giNew -join "`n") + "`n"), $script:Utf8) }
    if ($addTask) {
        $pwsh = (Get-Command pwsh).Source
        $action = New-ScheduledTaskAction -Execute $pwsh -WorkingDirectory $meta `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$(Join-Path $h 'src\run.ps1')`" -Scheduled"
        $trigger = New-ScheduledTaskTrigger -Daily -At '00:00'
        $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
    }
    if (-not $NoArchive) { & (Join-Path $src 'run.ps1') -ArchiveOnly -All }

    Use-Lib
    Write-Output 'Installed.'
    if ($NoSchedule) { Write-Output 'Scheduled runs are off (-NoSchedule).' }
    else { Write-Output "First scheduled run: $(Format-Time (Get-NextScheduled 'daily' (Get-NowEpoch)))." }
    Write-Output 'For a first look, in the clone folder:'
    Write-Output "  pwsh ./lessons.ps1 run -DryRun -MetaDir '$meta'"
    foreach ($p in Get-ReplaceMasters) { Write-ImportLine $p.Value.weekly.master }
}

# ------------------------------------------------------------------------------
function Invoke-Run {
    Use-Installed
    $a = @{}
    foreach ($k in 'Job', 'Since') { if ($PSBoundParameters.ContainsKey($k) -or (Get-Variable $k -ValueOnly)) { $v = Get-Variable $k -ValueOnly; if ($v) { $a[$k] = $v } } }
    foreach ($k in 'All', 'DryRun', 'ArchiveOnly', 'Yes', 'Scheduled') { if (Get-Variable $k -ValueOnly) { $a[$k] = $true } }
    & (Join-Path $h 'src/run.ps1') @a
    exit $LASTEXITCODE
}

# ------------------------------------------------------------------------------
function Invoke-Status {
    Use-Installed
    $now = Get-NowEpoch
    Write-Output 'Session lessons in:'
    Write-Output "  $meta"
    $s = $SlConfig.schedule
    Write-Output "Schedule: daily at $($s.dailyAt), weekly on $($s.weeklyDay) at $($s.weeklyAt)."
    Write-Output $(if (Get-OurTask) { 'Scheduled entry: registered (hourly).' } else { 'Scheduled entry: not registered.' })
    foreach ($j in 'daily', 'weekly') {
        if (Test-JobDue $j) { Write-Output "Next $j run: due now." }
        else { Write-Output "Next $j run: $(Format-Time (Get-NextScheduled $j $now))." }
    }
    foreach ($c in @(Get-Item -Path (Join-Path $SlState 'daily.cursor'), (Join-Path $SlState 'weekly-*.cursor') -ErrorAction SilentlyContinue)) {
        Write-Output "$($c.BaseName) progress: up to $(Format-Time ([long](Get-Content -Raw $c.FullName).Trim()))."
    }
    foreach ($j in 'daily', 'weekly') {
        $lrPath = Join-Path $SlState "last-run-$j.json"
        if (Test-Path -LiteralPath $lrPath) {
            $lr = Get-Content -Raw $lrPath | ConvertFrom-Json
            Write-Output "Last $j run: $(Format-Time $lr.finishedAt), $($lr.processed) processed, $($lr.failed) failed."
            if ($lr.error) { Write-Output "  Error: $("$($lr.error)".Substring(0, [Math]::Min(70, "$($lr.error)".Length)))" }
        } else { Write-Output "Last $j run: none yet." }
    }
    $g = Join-Path $SlState 'given-up.txt'
    $lines = if (Test-Path -LiteralPath $g) { @(Get-Content -LiteralPath $g | Where-Object { $_ }) } else { @() }
    if ($lines.Count) {
        Write-Output "Given up ($($lines.Count)), retried after removing the line from state/given-up.txt:"
        foreach ($l in $lines) { Write-Output "  $($l.Substring(0, [Math]::Min(76, $l.Length)))" }
    } else { Write-Output 'Given up: none.' }
    foreach ($p in Get-ReplaceMasters) {
        $m = $p.Value.weekly.master; $mp = Join-Path $meta $m
        $n = if (Test-Path -LiteralPath $mp) { @(Get-Content -LiteralPath $mp).Count } else { 0 }
        $k = & (Join-Path $h 'src/questions.ps1') count -Ext $p.Name
        Write-Output "$($p.Name): $(Split-Path -Leaf $m) $n lines, $k open question(s)."
        Write-ImportLine $m
    }
}

# ------------------------------------------------------------------------------
function Invoke-Uninstall {
    if (-not (Test-Path -LiteralPath (Join-Path $h 'state/install.json'))) { Write-Output "Nothing installed in $meta."; exit 0 }
    Use-Installed
    Assert-NotRunning
    $rec = $SlInstall.installed
    $items = [System.Collections.Generic.List[string]]::new()
    $tasks = @($rec.tasks | Where-Object { $_ }); $giLines = @($rec.gitignoreLines | Where-Object { $_ })
    if ($tasks.Count) { $items.Add('Remove the hourly scheduled task.') }
    if ($giLines.Count) { $items.Add("Remove the $($giLines.Count) .gitignore line(s) install added.") }
    $items.Add('Remove .claude/session-lessons/src/, state/, and staging/.')
    $purgePaths = @()
    if ($Purge) {
        foreach ($p in $SlConfig.extractions.PSObject.Properties) {
            $purgePaths += $p.Value.outputDir
            if ($p.Value.weekly) { $purgePaths += $p.Value.weekly.master }
        }
        $purgePaths += 'transcripts', '.claude/session-lessons'
        foreach ($p in $purgePaths) { $items.Add("Delete $p (purge).") }
        $items.Add("Delete this tool's logs (logs/**/*session-lessons-*) (purge).")
    } else { $items.Add('Keep config.json, every output, transcripts/, and the logs.') }
    Write-Output 'Uninstall session lessons from:'
    Write-Output "  $meta"
    foreach ($i in $items) { Write-Output "  - $i" }
    Write-Output 'The meta repo, its .git, and anything else in it stay.'
    Confirm-Change

    foreach ($t in $tasks) {
        $leaf = Split-Path -Leaf $t; $path = $t.Substring(0, $t.Length - $leaf.Length)
        Unregister-ScheduledTask -TaskPath $path -TaskName $leaf -Confirm:$false -ErrorAction SilentlyContinue
    }
    $gi = Join-Path $meta '.gitignore'
    if ($giLines.Count -and (Test-Path -LiteralPath $gi)) {
        $rest = @(Get-Content -LiteralPath $gi | Where-Object { $giLines -cnotcontains $_ })
        Write-Utf8 $gi $(if ($rest.Count) { ($rest -join "`n") + "`n" } else { '' })
    }
    foreach ($d in 'src', 'state', 'staging') {
        $p = Join-Path $h $d; if (Test-Path -LiteralPath $p) { Remove-Item -Recurse -Force -LiteralPath $p }
    }
    if ($Purge) {
        foreach ($p in $purgePaths) { $f = Join-Path $meta $p; if (Test-Path -LiteralPath $f) { Remove-Item -Recurse -Force -LiteralPath $f } }
        $logs = Join-Path $meta 'logs'
        if (Test-Path -LiteralPath $logs) { Get-ChildItem -LiteralPath $logs -Recurse -File -Filter '*session-lessons-*' | Remove-Item -Force }
    }
    Write-Output 'Uninstalled.'
}

switch ($Command) {
    'install' { Invoke-Install }
    'run' { Invoke-Run }
    'status' { Invoke-Status }
    'uninstall' { Invoke-Uninstall }
    default { Write-Output 'Usage: pwsh lessons.ps1 install|run|status|uninstall [options]'; Write-Output 'See README.md for the options.'; exit 1 }
}
# Explicit: callers such as setup/registry.ps1 read $LASTEXITCODE, which a
# script that ends without `exit` leaves at whatever it was before.
exit 0
