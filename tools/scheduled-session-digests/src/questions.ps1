#Requires -Version 7.4
# questions.ps1: the question queue, GitHub issues on the meta repo's origin.
#
#   -Mode collect  writes <outputDir>/answered/issue-<n>.md for each closed
#                  issue with the extraction's label that has a comment by the
#                  repo owner and no such file yet. Returns the warning ('' when none).
#   -Mode open     opens an issue for every "### " question in
#                  <outputDir>/questions/ whose title no issue with the label
#                  has, on a PRIVATE repo only. Returns @{ Repo; Warning }: Repo
#                  is <owner/repo> when the queue is active on a private repo.
#   -Mode count    returns the number of open issues with the label, or 'unknown'.
# The rules, messages, and gh calls are those of questions.sh. JSON is read
# with System.Text.Json, so no value is reinterpreted (ConvertFrom-Json would
# turn an ISO date in a title or comment into a DateTime).
#
# Cross-reference: src/questions.sh is the Bash twin.

param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('collect', 'open', 'count')][string]$Mode,
    [Parameter(Mandatory)][string]$Ext,
    [string]$Log
)

. (Join-Path $PSScriptRoot 'lib.ps1')
Initialize-SessionLessons
if ($Log) { $script:SlLog = $Log }

$e = $SlConfig.extractions.$Ext
$out = $e.outputDir
$label = if ($e.weekly.questions.label) { $e.weekly.questions.label } else { 'decision-question' }
$gh = $SlInstall.ghPath
$url = git -C $SlMeta remote get-url origin 2>$null
$repo = ''
if ($LASTEXITCODE -eq 0 -and "$url" -match 'github\.com[:/]([^/]+)/([^/]+)$') { $repo = "$($Matches[1])/$($Matches[2] -replace '\.git$', '')" }
$owner = $repo.Split('/')[0]

$off = ''
if ($e.weekly.questions.enabled -ne $true) { $off = 'questions are off in config' }
elseif (-not $gh -or -not ((Test-Path -LiteralPath $gh) -or (Get-Command $gh -ErrorAction SilentlyContinue))) { $off = 'gh not found (re-run install after installing it)' }
elseif (-not $repo) { $off = 'origin is not a GitHub repo' }
if ($off) {
    if ($Mode -ne 'count') { Write-Say "Question queue off: $off." }
    switch ($Mode) { 'collect' { return '' } 'open' { return @{ Repo = ''; Warning = '' } } 'count' { return 'unknown' } }
}

# Runs gh in the meta repo; returns the parsed JSON root, or $null when gh fails.
function Invoke-Gh {
    Push-Location -LiteralPath $SlMeta
    try { $o = & $gh @args 2>$null; $ok = $LASTEXITCODE -eq 0 } finally { Pop-Location }
    if (-not $ok) { return $null }
    $t = (@($o) -join "`n").Trim()
    if ($t -eq '') { return [System.Text.Json.JsonDocument]::Parse('{}').RootElement }
    [System.Text.Json.JsonDocument]::Parse($t).RootElement
}
# Runs gh in the meta repo for its exit code only (create prints plain text).
function Test-Gh {
    Push-Location -LiteralPath $SlMeta
    try { & $gh @args 2>$null | Out-Null; $LASTEXITCODE -eq 0 } finally { Pop-Location }
}
function Get-Clean($El) { $s = Get-Str $El; if ($null -eq $s) { $s = '' }; $s.Replace("`r", '').Trim($script:Ws) }

if ($Mode -eq 'count') {
    $j = Invoke-Gh issue list --repo $repo --state open --label $label --limit 1000 --json number
    if ($null -eq $j) { return 'unknown' }
    return "$($j.GetArrayLength())"
}

# Both modes need the label: gh issue create fails on a missing one.
if (-not (Test-Gh label create $label --repo $repo --force)) {
    $w = "questions ${Mode}: gh label create failed"; Write-Say $w
    if ($Mode -eq 'open') { return @{ Repo = ''; Warning = $w } } else { return $w }
}

if ($Mode -eq 'collect') {
    $user = Invoke-Gh api user
    $closed = if ($null -ne $user) { Invoke-Gh issue list --repo $repo --state closed --label $label --limit 1000 --json 'number,title,body,comments' }
    if ($null -eq $user -or $null -eq $closed) { $w = 'questions collect: gh failed'; Write-Say $w; return $w }
    $login = Get-Str (Get-Prop $user 'login'); if ($null -eq $login) { $login = '' }
    if ($login.ToLowerInvariant() -cne $owner.ToLowerInvariant()) {
        $w = "questions collect: gh is signed in as someone other than $owner, no answers read"; Write-Say $w; return $w
    }
    $dir = Join-Path $SlMeta "$out/answered"; $new = 0
    foreach ($i in $closed.EnumerateArray()) {
        $num = (Get-Prop $i 'number').GetRawText()
        $f = Join-Path $dir "issue-$num.md"
        if (Test-Path -LiteralPath $f) { continue }
        $cs = Get-Prop $i 'comments'
        $r = @(if ($null -ne $cs -and $cs.ValueKind -eq 'Array') {
            foreach ($c in $cs.EnumerateArray()) {
                $who = Get-Str (Get-Prop (Get-Prop $c 'author') 'login'); if ($null -eq $who) { $who = '' }
                if ($who.ToLowerInvariant() -cne $owner.ToLowerInvariant()) { continue }
                $t = Get-Clean (Get-Prop $c 'body'); if ($t) { $t }
            }
        })
        if (-not $r.Count) { continue }
        $body = Get-Clean (Get-Prop $i 'body'); if (-not $body) { $body = '(no description)' }
        $text = "## $(Get-Clean (Get-Prop $i 'title'))`n`n**Issue:** #$num`n`n### Situation`n`n$body`n`n### Reason`n`n" +
            ($r -join "`n`n") + "`n`n**Reason source:** stated`n"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Utf8 $f $text; $new++
    }
    Write-Say "Questions: $new answer(s) read from closed issues."
    return ''
}

# --- open ------------------------------------------------------------------------
$rv = Invoke-Gh repo view $repo --json visibility
if ($null -eq $rv) { $w = 'questions open: gh failed'; Write-Say $w; return @{ Repo = ''; Warning = $w } }
if ((Get-Str (Get-Prop $rv 'visibility')) -cne 'PRIVATE') {
    $w = "questions open: $repo is not private, no issues opened"; Write-Say $w; return @{ Repo = ''; Warning = $w }
}
$all = Invoke-Gh issue list --repo $repo --state all --label $label --limit 1000 --json title
if ($null -eq $all) { $w = 'questions open: gh failed'; Write-Say $w; return @{ Repo = ''; Warning = $w } }
$have = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($i in $all.EnumerateArray()) { $t = Get-Str (Get-Prop $i 'title'); if ($null -ne $t) { [void]$have.Add($t) } }
$w = ''; $new = 0
$qd = Join-Path $SlMeta "$out/questions"
if (Test-Path -LiteralPath $qd) {
    $names = [string[]]@(Get-ChildItem -LiteralPath $qd -File -Filter '*.md' | ForEach-Object Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    foreach ($n in $names) {
        # Each "### " line starts a question; the lines up to the next one are its body.
        $qs = [System.Collections.Generic.List[object]]::new()
        foreach ($l in (ConvertTo-Lines ([IO.File]::ReadAllText((Join-Path $qd $n), $script:Utf8)))) {
            if (Test-Starts $l '### ') { $qs.Add(@{ Title = $l.Substring(4).Trim($script:Ws); Body = [System.Collections.Generic.List[string]]::new() }) }
            elseif ($qs.Count) { $qs[$qs.Count - 1].Body.Add($l) }
        }
        foreach ($q in $qs) {
            if (-not $q.Title -or -not $have.Add($q.Title)) { continue }
            $qb = ($q.Body -join "`n").Trim($script:Ws)
            if (Test-Gh issue create --repo $repo --label $label --title $q.Title --body $qb) { $new++ }
            else { $w = 'questions open: gh issue create failed' }
        }
    }
}
Write-Say "Questions: $new issue(s) opened on $repo."
@{ Repo = $repo; Warning = $w }
