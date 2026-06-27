$ErrorActionPreference = 'Stop'

# Smoke tests for html/server.py (three-scope plugin model: local / project / user).
# Mirror of tests/smoke.sh — see that file's header for coverage notes.
# User-scope toggle writes the real ~/.claude/settings.json, so user scope is
# verified by read only; never POST a user-scope toggle here.

$Port = 17779
$ProjectDir = Join-Path $env:TEMP "smoke-$(Get-Random)"
$OtherDir   = "$ProjectDir-other"   # different project root; its plugin must be excluded
$PluginsDir = Join-Path $env:USERPROFILE ".claude\plugins"
$ServerProcess = $null

function Cleanup {
  if ($null -ne $ServerProcess -and -not $ServerProcess.HasExited) {
    $ServerProcess.Kill()
    $ServerProcess.WaitForExit(3000) | Out-Null
  }
  Remove-Item -Recurse -Force $ProjectDir -ErrorAction SilentlyContinue
  Remove-Item -Force "$PluginsDir\installed_plugins.json" -ErrorAction SilentlyContinue
}

# POST and return the HTTP status code (catching the throw on non-2xx).
function Get-PostStatus($path, $body) {
  try {
    $r = Invoke-WebRequest "http://localhost:$Port$path" -Method Post `
           -ContentType "application/json" -Body $body -UseBasicParsing -ErrorAction Stop
    return [int]$r.StatusCode
  } catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode.value__ }
    throw
  }
}

try {
  # ── Set up fixture files ──────────────────────────────────────────

  New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
  New-Item -ItemType Directory -Force -Path "$ProjectDir\.claude" | Out-Null

  # Replace placeholders with real temp dirs. Backslashes must be doubled for valid JSON.
  $fixture = Get-Content tests\fixtures\installed_plugins.json -Raw
  $fixture = $fixture.Replace('__PROJECT_ROOT__', $ProjectDir.Replace('\', '\\'))
  $fixture = $fixture.Replace('__OTHER_ROOT__',   $OtherDir.Replace('\', '\\'))
  $fixture | Set-Content "$PluginsDir\installed_plugins.json" -Encoding UTF8

  Copy-Item tests\fixtures\settings.local.json "$ProjectDir\.claude\settings.local.json"

  # ── Start server ──────────────────────────────────────────────────
  # On Windows CI runners (actions/setup-python) the executable is 'python'.

  $ServerProcess = Start-Process python `
    -ArgumentList "html\server.py", $Port, "`"$ProjectDir`"" `
    -PassThru -WindowStyle Hidden -WorkingDirectory (Get-Location)

  # Poll until ready (max 10s)
  $ready = $false
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep 1
    try {
      $null = Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -ErrorAction Stop
      $ready = $true
      break
    } catch { }
  }
  if (-not $ready) { throw "Server did not start within 10 seconds" }

  # ── /api/plugins ──────────────────────────────────────────────────

  $data = (Invoke-WebRequest "http://localhost:$Port/api/plugins" -UseBasicParsing).Content | ConvertFrom-Json

  foreach ($k in 'local','project','user','installedScopes','project_root') {
    if ($null -eq $data.PSObject.Properties[$k]) { throw "Missing key: $k" }
  }
  if ($data.PSObject.Properties['mock']) { throw "Unexpected mock flag with fixture present" }

  # local + project read temp settings we control → exact. user reads the real
  # ~/.claude/settings.json (server design), so assert containment there.
  $local   = @($data.local)
  $project = @($data.project)
  $user    = @($data.user)
  if ($local.Count   -ne 1 -or $local[0].id   -ne 'smoke-local@smoke-market')   { throw "local bucket wrong: $($local.id)" }
  if ($project.Count -ne 1 -or $project[0].id -ne 'smoke-project@smoke-market') { throw "project bucket wrong: $($project.id)" }
  if ($user.id -notcontains 'smoke-user@smoke-market') { throw "user bucket missing smoke-user: $($user.id)" }

  $allIds = ($local + $project + $user).id
  if ($allIds -contains 'smoke-other@smoke-market') { throw "cross-project plugin not excluded" }

  # Local row: field shape + values
  $lp = $local[0]
  foreach ($f in 'id','name','marketplace','version','scope','enabled','installed','skills','agents','hooks') {
    if ($null -eq $lp.PSObject.Properties[$f]) { throw "local row missing field: $f" }
  }
  if ($lp.name        -ne 'smoke-local')  { throw "wrong name: $($lp.name)" }
  if ($lp.marketplace -ne 'smoke-market') { throw "wrong marketplace: $($lp.marketplace)" }
  if ($lp.scope       -ne 'local')        { throw "wrong scope: $($lp.scope)" }
  if ($lp.version     -ne '1.0.0')        { throw "wrong version: $($lp.version)" }
  if ($lp.enabled     -ne $true)          { throw "expected local enabled=true" }
  if ($lp.installed   -ne $true)          { throw "expected local installed=true" }

  # Project + user enabled defaults
  if ($project[0].scope -ne 'project' -or $project[0].enabled -ne $true) { throw "project row/default wrong" }
  $su = $user | Where-Object { $_.id -eq 'smoke-user@smoke-market' } | Select-Object -First 1
  if ($su.scope -ne 'user' -or $su.enabled -ne $true) { throw "user row/default wrong" }

  # installedScopes map
  if (($data.installedScopes.'smoke-local@smoke-market'   -join ',') -ne 'local')   { throw "installedScopes local wrong" }
  if (($data.installedScopes.'smoke-project@smoke-market' -join ',') -ne 'project') { throw "installedScopes project wrong" }
  if (($data.installedScopes.'smoke-user@smoke-market'    -join ',') -ne 'user')    { throw "installedScopes user wrong" }
  if ($data.installedScopes.PSObject.Properties['smoke-other@smoke-market']) { throw "installedScopes leaked cross-project plugin" }

  # ── /api/marketplace ──────────────────────────────────────────────

  $mp = (Invoke-WebRequest "http://localhost:$Port/api/marketplace" -UseBasicParsing).Content | ConvertFrom-Json
  if ($null -eq $mp.PSObject.Properties['marketplaces']) { throw "marketplace response missing 'marketplaces'" }

  # ── /api/toggle happy paths ───────────────────────────────────────

  $bodyLocal = '{"id":"smoke-local@smoke-market","enabled":false,"scope":"local"}'
  $tr = (Invoke-WebRequest "http://localhost:$Port/api/toggle" -Method Post -ContentType "application/json" -Body $bodyLocal -UseBasicParsing).Content | ConvertFrom-Json
  if ($tr.ok -ne $true) { throw "local toggle not ok" }

  $bodyProject = '{"id":"smoke-project@smoke-market","enabled":false,"scope":"project"}'
  $tr = (Invoke-WebRequest "http://localhost:$Port/api/toggle" -Method Post -ContentType "application/json" -Body $bodyProject -UseBasicParsing).Content | ConvertFrom-Json
  if ($tr.ok -ne $true) { throw "project toggle not ok" }

  $data2 = (Invoke-WebRequest "http://localhost:$Port/api/plugins" -UseBasicParsing).Content | ConvertFrom-Json
  if (@($data2.local)[0].enabled   -ne $false) { throw "local toggle not persisted" }
  if (@($data2.project)[0].enabled -ne $false) { throw "project toggle not persisted" }

  # ── /api/toggle validation (all expect HTTP 400) ──────────────────

  $cases = @(
    @{ d = 'invalid id (no @)';     b = '{"id":"noatsign","enabled":true,"scope":"local"}' },
    @{ d = 'missing scope';         b = '{"id":"smoke-local@smoke-market","enabled":true}' },
    @{ d = 'invalid scope';         b = '{"id":"smoke-local@smoke-market","enabled":true,"scope":"global"}' },
    @{ d = 'non-bool enabled';      b = '{"id":"smoke-local@smoke-market","enabled":"yes","scope":"local"}' },
    @{ d = 'id not in given scope'; b = '{"id":"smoke-user@smoke-market","enabled":true,"scope":"local"}' }
  )
  foreach ($c in $cases) {
    $code = Get-PostStatus "/api/toggle" $c.b
    if ($code -ne 400) { throw "toggle '$($c.d)': expected HTTP 400, got $code" }
  }

  # ── /api/set-project validation ───────────────────────────────────

  $code = Get-PostStatus "/api/set-project" '{"path":"C:\\no\\such\\dir\\smoke-xyz"}'
  if ($code -ne 400) { throw "set-project invalid path: expected HTTP 400, got $code" }

  # ── mock fallback (run last: removes the fixture) ──────────────────

  Remove-Item -Force "$PluginsDir\installed_plugins.json"
  $dm = (Invoke-WebRequest "http://localhost:$Port/api/plugins" -UseBasicParsing).Content | ConvertFrom-Json
  if ($dm.mock -ne $true) { throw "expected mock:true when installed_plugins.json is missing" }
  # build_sections unions mock-installed with settings, so use containment.
  if (@($dm.local).id -notcontains 'ceh-dev-tools@ceh-plugins')  { throw "mock local wrong: $(@($dm.local).id)" }
  if (@($dm.user).id  -notcontains 'frontend-design@anthropic') { throw "mock user wrong: $(@($dm.user).id)" }

  Write-Host "OK: all smoke tests passed"

} finally {
  Cleanup
}
