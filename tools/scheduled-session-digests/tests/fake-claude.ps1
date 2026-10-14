# Fake `claude` for the tests. Never calls a model.
#
# Reads the prompt (last argument) and the staged input (pipeline), then prints
# a preamble and one canned part per requested extraction. Controlled by files
# in its working directory, the meta repo, under .fake-claude/:
#   exit1      present: print an error and exit 1
#   exit1-stdout  present: print an error on stdout, as claude does for an
#              API error, and exit 1
#   fail.txt   lines "<extraction>:<uuid>": print a truncated part instead
#   none.txt   lines "<extraction>:<uuid>": print the "nothing found" form
#   calls.log  appended: "<uuid>: <requested extractions>" per call
# The weekly control files are the ones fake-claude.sh lists.
#
# Cross-reference: tests/fake-claude.sh behaves the same.

$prompt = $args[-1]
$stdin = @($input) -join "`n"
$dir = Join-Path (Get-Location) '.fake-claude'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
if (Test-Path (Join-Path $dir 'exit1')) { [Console]::Error.WriteLine('fake claude: simulated failure'); exit 1 }
if (Test-Path (Join-Path $dir 'exit1-stdout')) { ''; 'API Error: 529 Overloaded.'; exit 1 }

$utf8 = [Text.UTF8Encoding]::new($false)
if (($prompt -split "`n")[0].TrimEnd("`r") -ceq '# Weekly decisions merge') {
    $first = ([regex]::Match($stdin, '(?m)^## Source: (.*)$')).Groups[1].Value.TrimEnd("`r")
    [IO.File]::AppendAllText((Join-Path $dir 'calls.log'), "weekly-decisions: $first`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $dir "input-$first"), $stdin.TrimEnd("`n"), $utf8)
    'Here is the merge.'
    if (Test-Path (Join-Path $dir 'weekly-decisions-bad')) { 'garbage'; exit 0 }
    $custom = Join-Path $dir 'weekly-decisions-answer.md'
    if (Test-Path $custom) { [IO.File]::ReadAllText($custom, $utf8).TrimEnd("`n"); exit 0 }
    "<<<extraction:soul>>>`n# SOUL`n`n## Priorities`n`n1. Synthetic priority from $first.`n`n## Rules`n`n- When synthetic, prefer $first.`n<<<extraction:questions>>>`n### Synthetic question from ${first}?`n`nContext: synthetic."
    exit 0
}
if (($prompt -split "`n")[0].TrimEnd("`r") -ceq '# Weekly lessons merge') {
    $first = ([regex]::Match($stdin, '(?m)^## Source: (.*)$')).Groups[1].Value.TrimEnd("`r")
    [IO.File]::AppendAllText((Join-Path $dir 'calls.log'), "weekly: $first`n", $utf8)
    'Here is the merge.'
    $bad = Join-Path $dir 'weekly-bad'
    if ((Test-Path $bad) -and ((Get-Item $bad).Length -eq 0 -or @(Get-Content $bad) -ccontains $first)) { 'garbage'; exit 0 }
    $custom = Join-Path $dir 'weekly-answer.md'
    if (Test-Path $custom) { [IO.File]::ReadAllText($custom, $utf8).TrimEnd("`n"); exit 0 }
    "## Tooling`n`n### Weekly lesson from $first`n**Source**: $first`n**Lesson**: A synthetic generic rule.`n**Apply when**: Always.`n**Tags**: #synthetic`n`n### Second weekly lesson from $first`n**Lesson**: Another synthetic rule."
    exit 0
}
$uuid = ([regex]::Match($stdin, '(?m)^UUID: (.*)$')).Groups[1].Value.TrimEnd("`r")
$date = ([regex]::Match($stdin, '(?m)^Date: (.*)$')).Groups[1].Value.TrimEnd("`r")
$names = @([regex]::Matches($prompt, '(?m)^<<<extraction:(.*)>>>$') | ForEach-Object { $_.Groups[1].Value })
[IO.File]::AppendAllText((Join-Path $dir 'calls.log'), "${uuid}: $($names -join ' ')`n", $utf8)
$fail = @(); $failFile = Join-Path $dir 'fail.txt'
if (Test-Path $failFile) { $fail = @(Get-Content $failFile) }
$noneList = @(); $noneFile = Join-Path $dir 'none.txt'
if (Test-Path $noneFile) { $noneList = @(Get-Content $noneFile) }

$d = [char]0x2014
$header = "$d $date`n**Session**: $uuid`n**Title**: Synthetic`n**Project**: synthetic"
'Here are the parts you asked for.'
foreach ($n in $names) {
    "<<<extraction:$n>>>"
    if ($fail -ccontains "${n}:$uuid") { 'truncated'; continue }
    if ($noneList -ccontains "${n}:$uuid") { "# Decisions $header`n`n_No decisions extracted from this session._"; continue }
    if ($n -eq 'decisions') {
        "# Decisions $header`n`n## Synthetic decision`n`n- **Situation:** A synthetic choice.`n- **Chosen:** Option A.`n- **Reason:** none given`n- **Reason source:** none"
    } elseif ($n -eq 'lessons') {
        "# Lessons $d $date`n**Session**: $uuid`n**Title**: Synthetic`n**Project**: synthetic`n`n## $date $d Synthetic lesson`n`n**What happened:** A synthetic mistake.`n`n**Lesson:** A synthetic rule."
    } else { "$n part for $uuid" }
}
exit 0
