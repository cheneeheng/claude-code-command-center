# Fake `gh` for the tests. Never reaches GitHub. The control files and log
# are the ones tests/fake-gh.sh lists.
#
# Cross-reference: tests/fake-gh.sh behaves the same.

$dir = Join-Path (Get-Location) '.fake-gh'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$a = @($args | ForEach-Object { "$_" })
$logged = [System.Collections.Generic.List[string]]::new(); $limit = 30; $state = ''; $title = ''
for ($i = 0; $i -lt $a.Count; $i++) {
    if ($a[$i] -ceq '--body') { $i++; continue }
    if ($a[$i] -ceq '--limit') { $limit = [int]$a[$i + 1] }
    elseif ($a[$i] -ceq '--state') { $state = $a[$i + 1] }
    elseif ($a[$i] -ceq '--title') { $title = $a[$i + 1] }
    $logged.Add($a[$i])
}
[IO.File]::AppendAllText((Join-Path $dir 'calls.log'), ($logged -join ' ') + "`n", $utf8)
# Run in-process as a .ps1, so stderr goes through Write-Error: the caller's 2>&1
# catches it the way it catches a native gh's stderr.
if (Test-Path (Join-Path $dir 'fail')) { Write-Error 'fake gh: simulated failure' -ErrorAction Continue; exit 1 }
if ((Test-Path (Join-Path $dir 'deny-create')) -and "$($a[0]) $($a[1])" -ceq 'issue create') {
    Write-Error 'GraphQL: Resource not accessible (createIssue)' -ErrorAction Continue; exit 1
}

function Read-Canned([string]$Name, [string]$Default) {
    $f = Join-Path $dir $Name
    if (Test-Path $f) { [IO.File]::ReadAllText($f, $utf8).TrimEnd("`n") } else { $Default }
}
switch -CaseSensitive ("$($a[0]) $($a[1])") {
    'api user' { Read-Canned 'user.json' '{"login":"synth-owner"}' }
    'repo view' { Read-Canned 'repo.json' '{"visibility":"PRIVATE"}' }
    'label create' { 'Label created.' }
    'issue list' {
        $doc = [System.Text.Json.JsonDocument]::Parse((Read-Canned "$state.json" '[]'))
        '[' + (@($doc.RootElement.EnumerateArray() | Select-Object -First $limit | ForEach-Object { $_.GetRawText() }) -join ',') + ']'
    }
    'issue create' {
        [IO.File]::AppendAllText((Join-Path $dir 'created.txt'), "$title`n", $utf8)
        'https://github.com/synth-owner/synth-meta/issues/99'
    }
}
exit 0
