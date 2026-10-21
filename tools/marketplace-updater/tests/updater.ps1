# Runs the real worker against a stub claude CLI and checks which commands it issued.
#   pwsh -NoProfile -File tests/updater.ps1
$ErrorActionPreference = 'Stop'
$worker = Join-Path $PSScriptRoot '..\marketplace-updater.ps1'
$stub   = Join-Path $PSScriptRoot 'stub-claude.ps1'

$tmp   = Join-Path ([IO.Path]::GetTempPath()) "mu-test-$([guid]::NewGuid().ToString('N'))"
$repoA = Join-Path $tmp 'repoA'
$repoB = Join-Path $tmp 'repoB'
$gone  = Join-Path $tmp 'gone'
New-Item -ItemType Directory -Force -Path $repoA, $repoB | Out-Null
$env:C4_STUB_LIST = Join-Path $tmp 'list.json'
$env:C4_STUB_LOG  = Join-Path $tmp 'calls.log'

function Plugin($id, $scope, $path) { @{ id = $id; scope = $scope; projectPath = $path } }

# Writes config + plugin list, runs the worker, leaves $exit, $calls (stub log) and $log (run.log).
function Run($marketplaces, $repos, $plugins, [switch]$DryRun) {
    Remove-Item $env:C4_STUB_LOG, (Join-Path $tmp 'run.log') -ErrorAction SilentlyContinue
    ConvertTo-Json -InputObject @($plugins) | Set-Content $env:C4_STUB_LIST
    @{ marketplaces = $marketplaces; repos = $repos } | ConvertTo-Json | Set-Content (Join-Path $tmp 'config.json')
    & $worker -ConfigFile (Join-Path $tmp 'config.json') -ClaudeCommand $stub -DryRun:$DryRun *> $null
    $script:exit  = $LASTEXITCODE
    $script:calls = @(Get-Content $env:C4_STUB_LOG -ErrorAction SilentlyContinue | ForEach-Object { $_ -replace [regex]::Escape($tmp), '<tmp>' -replace '\\', '/' })
    $script:log   = Get-Content -Raw (Join-Path $tmp 'run.log') -ErrorAction SilentlyContinue
}
function Updates { @($calls | Where-Object { $_ -like '*plugin update*' }) }
$fail = 0
function Check($ok, $what) { if ($ok) { "ok   $what" } else { "FAIL $what"; $script:fail++ } }

$plugins = @(
    (Plugin 'hit@mk' 'local' $repoA)          # configured marketplace + repo: updated
    (Plugin 'proj@mk' 'project' $repoA)       # project scope counts too
    (Plugin 'hit@mk' 'local' $repoA.ToUpper())  # the list can hold one install twice, differing in case
    (Plugin 'user@mk' 'user' $null)           # user scope: not a repo install
    (Plugin 'other@else' 'local' $repoA)      # marketplace not configured
    (Plugin 'elsewhere@mk' 'local' $repoB)    # repo not configured
    (Plugin 'broken@bad' 'local' $repoA)      # marketplace refresh fails: skipped
)

Run @('mk', 'bad') @($repoA) $plugins
Check ($exit -eq 2) 'a failed marketplace refresh exits 2'
Check ($calls -contains '<tmp>/repoA|plugin update hit@mk --scope local') 'local plugin updated from inside its repo'
Check ($calls -contains '<tmp>/repoA|plugin update proj@mk --scope project') 'project plugin updated'
Check ((Updates).Count -eq 2) 'nothing else updated: duplicate, user scope, other marketplace, other repo, failed refresh'
Check ($log -match 'FAILED refreshing marketplace bad') 'run.log records the failed refresh'

Run @('mk', 'bad') @($repoA) $plugins -DryRun
Check ($exit -eq 0) 'dry run exits 0'
Check (-not ($calls -like '*plugin update*') -and -not ($calls -like '*marketplace update*')) 'dry run issues no update'

Run @('mk') @($repoA, $repoB) @((Plugin 'hit@mk' 'local' $repoA))
Check ($exit -eq 0) 'a clean run exits 0'
Check ($log -match 'Nothing to update in .*repoB') 'a repo with no matching plugin is logged'

Run @('mk') @($gone) @((Plugin 'hit@mk' 'local' $gone))
Check ($exit -eq 2 -and (Updates).Count -eq 0 -and $log -match 'repo folder is missing') 'a missing repo folder fails without updating'

$env:C4_STUB_LIST_FAIL = '1'
Run @('mk') @($repoA) $plugins
Check ($exit -eq 2 -and (Updates).Count -eq 0 -and $log -notmatch 'Nothing to update') 'a failed plugin list exits 2, not "nothing to update"'
$env:C4_STUB_LIST_FAIL = ''

Run @('mk') @() $plugins
Check ($exit -eq 1) 'a config without repos exits 1'

Remove-Item $tmp -Recurse -Force
if ($fail) { exit 1 }
