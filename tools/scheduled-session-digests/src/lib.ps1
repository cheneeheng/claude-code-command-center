#Requires -Version 7.4
# lib.ps1: helpers shared by the PowerShell pipeline scripts. Dot-sourced.
#
# Cross-reference: src/lib.sh, src/clean.jq, and src/split.jq are the Bash
# twins. Keep both behaviourally identical (paths, encoding, lock format, cutoff
# rules, the cleanup rules in Convert-Transcript, the split in Split-Answer).
# 7.4 is the minimum because older versions drop empty-string arguments
# (`--tools ""`) when calling a native program.

$ErrorActionPreference = 'Stop'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:SlLog = $null

# The meta repo is the one this installed copy lives in: <meta>/.claude/session-lessons/src.
function Initialize-SessionLessons {
    $script:SlSrc = $PSScriptRoot
    $script:SlMeta = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $script:SlHome = Join-Path $script:SlMeta '.claude/session-lessons'
    $script:SlState = Join-Path $script:SlHome 'state'
    $script:SlStaging = Join-Path $script:SlHome 'staging'
    $script:SlConfig = Get-Content -Raw (Join-Path $script:SlHome 'config.json') | ConvertFrom-Json
    $script:SlInstall = Get-Content -Raw (Join-Path $script:SlState 'install.json') | ConvertFrom-Json
}

# Prints a line and, when a run log is open, appends it there too.
function Write-Say([string]$Text) {
    [Console]::Out.Write($Text + "`n")
    if ($script:SlLog) { [IO.File]::AppendAllText($script:SlLog, $Text + "`n", $script:Utf8) }
}

# Rule 6: reserved filename characters and ASCII whitespace runs become '_'.
function Get-SafeTitle([string]$Title) { ($Title -replace '[\\/:*?"<>|]', '_') -replace '[ \t\n\r\v\f]+', '_' }

# Mirrors src/split.jq: one part per requested name, first occurrence wins.
function Split-Answer([string]$Text, [string[]]$Names) {
    $parts = [ordered]@{}; $cur = $null
    foreach ($raw in $Text.Split("`n")) {
        $line = $raw -replace "`r$", ''
        if ($line -cmatch '^<<<extraction:([A-Za-z0-9_-]+)>>>$') {
            $m = $Matches[1]
            $cur = if ($Names -ccontains $m -and -not $parts.Contains($m)) { $m } else { '' }
            if ($cur) { $parts[$cur] = [System.Collections.Generic.List[string]]::new() }
        } elseif ($cur) { $parts[$cur].Add($line) }
    }
    $out = @{}
    foreach ($k in $parts.Keys) {
        $s = ($parts[$k] -join "`n").Trim($script:Ws)
        if ($s -match '^```[^\n]*\n' -and $s -match '\n```$') {
            $s = ($s -replace '^```[^\n]*\n', '' -replace '\n```$', '').Trim($script:Ws)
        }
        $out[$k] = $s + "`n"
    }
    $out
}

function Get-NowEpoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Get-MtimeEpoch($File) { [DateTimeOffset]::new($File.LastWriteTimeUtc).ToUnixTimeSeconds() }
function Get-LocalDate([long]$Epoch) { [DateTimeOffset]::FromUnixTimeSeconds($Epoch).ToLocalTime().ToString('yyyy-MM-dd') }
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:Utf8) }

# Claude Code names a project folder after the absolute path of its working
# directory, with every character that is not a letter or digit replaced by '-'.
function ConvertTo-ProjectDirName([string]$Path) { $Path -replace '[^A-Za-z0-9]', '-' }

# --- lock ------------------------------------------------------------------
# state/run.lock is {"pid":N,"startTime":E}, E = the process start time as UTC
# Unix seconds, truncated. Live = that PID exists and its start time matches
# within 1 second. Anything else is stale and replaced.

function Get-ProcessStartEpoch([int]$ProcessId) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    [DateTimeOffset]::new($p.StartTime.ToUniversalTime()).ToUnixTimeSeconds()
}

function Test-LockLive([string]$Lock) {
    try { $l = Get-Content -Raw $Lock | ConvertFrom-Json } catch { return $false }
    if ($null -eq $l.pid -or $null -eq $l.startTime) { return $false }
    $actual = Get-ProcessStartEpoch ([int]$l.pid)
    if ($null -eq $actual) { return $false }
    [Math]::Abs($actual - [long]$l.startTime) -le 1
}

# Takes the lock, or exits 0 when another run holds it. Release-Lock frees it.
function Enter-Lock {
    New-Item -ItemType Directory -Force -Path $script:SlState | Out-Null
    $lock = Join-Path $script:SlState 'run.lock'
    $tmp = Join-Path $script:SlState (".lock." + [Guid]::NewGuid().ToString('N'))
    Write-Utf8 $tmp ('{"pid":' + $PID + ',"startTime":' + (Get-ProcessStartEpoch $PID) + "}`n")
    foreach ($try in 1, 2) {
        try { [IO.File]::Move($tmp, $lock); $script:SlLock = $lock; return }
        catch [System.IO.IOException] {
            if ($try -eq 1 -and -not (Test-LockLive $lock)) { Remove-Item -Force $lock; continue }
            Remove-Item -Force $tmp
            $holder = try { (Get-Content -Raw $lock | ConvertFrom-Json).pid } catch { '?' }
            Write-Output "Another run is in progress (pid $holder)."
            exit 0
        }
    }
}

function Exit-Lock { if ($script:SlLock) { Remove-Item -Force -ErrorAction SilentlyContinue $script:SlLock } }

# --- transcript cleanup (rules v1) -------------------------------------------
# Mirrors src/clean.jq exactly. Uses System.Text.Json, so no value is ever
# reinterpreted (ConvertFrom-Json would turn ISO date strings into DateTime).

$script:Ws = [char[]]@(32, 9, 10, 13, 11, 12)
$script:RemovedTags = 'system-reminder', 'task-notification', 'command-message',
    'local-command-stdout', 'local-command-stderr', 'local-command-caveat',
    'bash-stdout', 'bash-stderr'
$script:UnwrappedTags = 'command-name', 'command-args', 'bash-input'
$script:Interrupts = '[Request interrupted by user]', '[Request interrupted by user for tool use]'

function Get-Prop($El, [string]$Name) {
    if ($null -eq $El -or $El.ValueKind -ne 'Object') { return $null }
    $v = [System.Text.Json.JsonElement]::new()
    if ($El.TryGetProperty($Name, [ref]$v)) { return $v }
    $null
}
function Get-Str($El) { if ($null -ne $El -and $El.ValueKind -eq 'String') { $El.GetString() } else { $null } }
function Test-True($El) { $null -ne $El -and $El.ValueKind -eq 'True' }

# Code points: UTF-16 length minus the low halves of surrogate pairs.
function Get-CodePointLength([string]$S) { $S.Length - [regex]::Matches($S, '[\uDC00-\uDFFF]').Count }
function Get-CodePointPrefix([string]$S, [int]$N) {
    $i = 0; $c = 0
    while ($i -lt $S.Length -and $c -lt $N) {
        if ([char]::IsHighSurrogate($S[$i]) -and $i + 1 -lt $S.Length -and [char]::IsLowSurrogate($S[$i + 1])) { $i += 2 } else { $i++ }
        $c++
    }
    $S.Substring(0, $i)
}

function ConvertTo-UserText([string]$S) {
    foreach ($t in $script:RemovedTags) { $S = [regex]::Replace($S, "<$t>[\s\S]*?</$t>", '') }
    foreach ($t in $script:UnwrappedTags) { $S = [regex]::Replace($S, "<$t>([\s\S]*?)</$t>", '$1') }
    $S.Trim($script:Ws)
}

function Get-TextOf($Content) {
    if ($null -eq $Content) { return '' }
    if ($Content.ValueKind -eq 'String') { return $Content.GetString() }
    if ($Content.ValueKind -ne 'Array') { return '' }
    $parts = foreach ($b in $Content.EnumerateArray()) {
        if ((Get-Str (Get-Prop $b 'type')) -eq 'text') { $t = Get-Str (Get-Prop $b 'text'); if ($null -eq $t) { '' } else { $t } }
    }
    @($parts) -join "`n"
}

function Format-Block([string]$Label, [string]$Text) {
    "[$Label]`n" + $(if ($Text -eq '') { '' } else { "$Text`n" }) + "`n"
}

function Convert-Transcript([string]$Path) {
    # Tools is case-sensitive, like jq object keys.
    $st = @{ Title = $null; Cwd = $null; Turns = 0; Out = [System.Text.StringBuilder]::new()
             Tools = [hashtable]::new([StringComparer]::Ordinal) }

    $addUser = {
        param([string]$S)
        if ($script:Interrupts -ccontains $S.Trim($script:Ws)) { [void]$st.Out.Append((Format-Block 'INTERRUPTED' '')); return }
        $t = ConvertTo-UserText $S
        if ($t -ne '') { [void]$st.Out.Append((Format-Block 'USER' $t)); $st.Turns++ }
    }

    foreach ($line in [IO.File]::ReadLines($Path, $script:Utf8)) {
        try { $doc = [System.Text.Json.JsonDocument]::Parse($line) } catch { continue }
        $e = $doc.RootElement
        if ($e.ValueKind -ne 'Object') { continue }
        $type = Get-Str (Get-Prop $e 'type')

        if ($null -eq $st.Title -and $type -eq 'custom-title') {
            $ct = Get-Str (Get-Prop $e 'customTitle'); if ($ct) { $st.Title = $ct }
        }
        if ($null -eq $st.Cwd) { $cwd = Get-Str (Get-Prop $e 'cwd'); if ($cwd) { $st.Cwd = $cwd } }
        if (Test-True (Get-Prop $e 'isSidechain')) { continue }

        if ($type -eq 'user') {
            if ((Test-True (Get-Prop $e 'isMeta')) -or (Test-True (Get-Prop $e 'isCompactSummary'))) { continue }
            $content = Get-Prop (Get-Prop $e 'message') 'content'
            if ($null -ne $content -and $content.ValueKind -eq 'Array') {
                $tur = Get-Prop $e 'toolUseResult'
                $hasText = $false
                foreach ($b in $content.EnumerateArray()) {
                    $bt = Get-Str (Get-Prop $b 'type')
                    if ($bt -eq 'text') { $hasText = $true; continue }
                    if ($bt -ne 'tool_result') { continue }
                    $id = Get-Str (Get-Prop $b 'tool_use_id'); if ($null -eq $id) { $id = '' }
                    $name = $st.Tools[$id]
                    if ($name -eq 'AskUserQuestion') {
                        $answers = Get-Prop $tur 'answers'
                        if ($null -ne $answers -and $answers.ValueKind -eq 'Object') {
                            $ann = Get-Prop $tur 'annotations'
                            $lines = foreach ($p in $answers.EnumerateObject()) {
                                $v = $p.Value
                                $a = if ($v.ValueKind -eq 'Array') { @($v.EnumerateArray() | ForEach-Object { if ($_.ValueKind -eq 'String') { $_.GetString() } else { $_.GetRawText() } }) -join ', ' }
                                     elseif ($v.ValueKind -eq 'String') { $v.GetString() } else { $v.GetRawText() }
                                $n = Get-Str (Get-Prop (Get-Prop $ann $p.Name) 'notes')
                                "Q: $($p.Name)`nA: $a" + $(if ($n) { "`nNotes: $n" } else { '' })
                            }
                            $atext = @($lines) -join "`n"
                        } else {
                            $atext = (Get-TextOf (Get-Prop $b 'content')).Trim($script:Ws)
                        }
                        if ($atext -ne '') { [void]$st.Out.Append((Format-Block 'ANSWER' $atext)); $st.Turns++ }
                    } elseif ((Get-Str $tur) -eq 'User rejected tool use') {
                        $label = if ($null -ne $name) { $name } else { 'unknown' }
                        [void]$st.Out.Append((Format-Block "USER REJECTED $label" ''))
                    }
                }
                if ($hasText) { & $addUser (Get-TextOf $content) }
            } else {
                & $addUser (Get-TextOf $content)
            }
        } elseif ($type -eq 'assistant') {
            $content = Get-Prop (Get-Prop $e 'message') 'content'
            if ($null -eq $content) { continue }
            $blocks = if ($content.ValueKind -eq 'String') { ,@{ type = 'text'; text = $content.GetString() } }
                      elseif ($content.ValueKind -eq 'Array') { @($content.EnumerateArray()) } else { @() }
            foreach ($b in $blocks) {
                if ($b -is [hashtable]) { $bt = $b.type; $text = $b.text }
                else { $bt = Get-Str (Get-Prop $b 'type'); $text = Get-Str (Get-Prop $b 'text') }
                if ($bt -eq 'text') {
                    $t = $(if ($null -eq $text) { '' } else { $text }).Trim($script:Ws)
                    if ($t -ne '') {
                        if ((Get-CodePointLength $t) -gt 10000) { $t = (Get-CodePointPrefix $t 10000) + "`n[...truncated]" }
                        [void]$st.Out.Append((Format-Block 'ASSISTANT' $t))
                    }
                } elseif ($bt -eq 'tool_use') {
                    $id = Get-Str (Get-Prop $b 'id'); if ($null -eq $id) { $id = '' }
                    $name = Get-Str (Get-Prop $b 'name'); if ($null -eq $name) { $name = '' }
                    $st.Tools[$id] = $name
                    if ($name -eq 'AskUserQuestion') {
                        $qs = Get-Prop (Get-Prop $b 'input') 'questions'
                        if ($null -ne $qs -and $qs.ValueKind -eq 'Array') {
                            foreach ($q in $qs.EnumerateArray()) {
                                $qt = Get-Str (Get-Prop $q 'question'); if ($null -eq $qt) { $qt = '' }
                                $opts = Get-Prop $q 'options'
                                $ol = if ($null -ne $opts -and $opts.ValueKind -eq 'Array') {
                                    foreach ($o in $opts.EnumerateArray()) {
                                        $lb = Get-Str (Get-Prop $o 'label'); if ($null -eq $lb) { $lb = '' }
                                        $d = Get-Str (Get-Prop $o 'description')
                                        "- $lb" + $(if ($d) { ": $d" } else { '' })
                                    }
                                }
                                [void]$st.Out.Append((Format-Block 'QUESTION' ("$qt`nOptions:`n" + (@($ol) -join "`n"))))
                            }
                        }
                    }
                }
            }
        } elseif ($type -eq 'attachment') {
            $att = Get-Prop $e 'attachment'
            if ((Get-Str (Get-Prop $att 'type')) -eq 'queued_command' -and (Test-True (Get-Prop $att 'humanTurn'))) {
                $p = Get-Str (Get-Prop $att 'prompt')
                if ($null -ne $p) { & $addUser $p }
            }
        }
    }

    $project = 'unknown'
    if ($st.Cwd) {
        $parts = @(($st.Cwd -replace '[/\\]+$', '') -split '[/\\]' | Where-Object { $_ -ne '' })
        if ($parts.Count -gt 0) { $project = $parts[-1] }
    }
    [pscustomobject]@{ Title = $st.Title; Project = $project; Turns = $st.Turns; Body = $st.Out.ToString() }
}
