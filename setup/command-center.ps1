#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install / uninstall the Command Center tools and track what is installed.

.DESCRIPTION
    A thin orchestrator over each tool's own setup script (see registry.ps1). It never
    reimplements a tool's install logic; it delegates, then records the result in a manifest
    under ~/.claude-command-center/manifest.json so you can see what is installed on this
    machine and reverse it later (uninstall replays the recorded params).

.EXAMPLE
    ./command-center.ps1 list
    ./command-center.ps1 status
    ./command-center.ps1 install -Member statusline-hook
    ./command-center.ps1 install -All            # reads ~/.claude-command-center/config.json
    ./command-center.ps1 uninstall -Member file-sync
    ./command-center.ps1 uninstall -All
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'install', 'uninstall')]
    [string]$Command = 'status',

    # Target a single member by name (mutually exclusive with -All).
    [string]$Member,

    # Target every managed member.
    [switch]$All,

    # Override the config file path (default: ~/.claude-command-center/config.json).
    [string]$Config
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/registry.ps1"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Registry = Get-CommandCenterRegistry -RepoRoot $RepoRoot

$StateDir     = Join-Path $env:USERPROFILE '.claude-command-center'
$ManifestPath = Join-Path $StateDir 'manifest.json'
$ConfigPath   = if ($Config) { $Config } else { Join-Path $StateDir 'config.json' }

# ---- Manifest + config helpers ---------------------------------------------

function Get-Manifest {
    if (Test-Path $ManifestPath) {
        $raw = Get-Content -Raw $ManifestPath
        if ($raw.Trim()) { return $raw | ConvertFrom-Json }
    }
    [pscustomobject]@{ version = 1; updated_at = $null; members = [pscustomobject]@{} }
}

function Save-Manifest($Manifest) {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force $StateDir | Out-Null }
    $Manifest.updated_at = (Get-Date).ToString('o')
    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $ManifestPath -Encoding utf8
}

function Get-Entry($Manifest, $Name) {
    if ($Manifest.members.PSObject.Properties.Name -contains $Name) { return $Manifest.members.$Name }
    $null
}

function Set-Entry($Manifest, $Name, $Entry) {
    $Manifest.members | Add-Member -NotePropertyName $Name -NotePropertyValue $Entry -Force
}

function Get-Config {
    if (Test-Path $ConfigPath) {
        $raw = Get-Content -Raw $ConfigPath
        if ($raw.Trim()) { return $raw | ConvertFrom-Json }
    }
    [pscustomobject]@{}
}

function Get-MemberConfig($Cfg, $Name) {
    if ($Cfg.PSObject.Properties.Name -contains $Name) { return $Cfg.$Name }
    $null
}

# A member's required config is satisfied when every RequiredConfig key is present + non-empty.
function Test-ConfigComplete($Desc, $MemberCfg) {
    foreach ($key in $Desc.RequiredConfig) {
        if (-not $MemberCfg -or
            ($MemberCfg.PSObject.Properties.Name -notcontains $key) -or
            (-not $MemberCfg.$key)) {
            return $false
        }
    }
    $true
}

function Resolve-Targets {
    if ($Member -and $All) { throw 'Specify -Member or -All, not both.' }
    if ($All)    { return $Registry }
    if ($Member) {
        $d = $Registry | Where-Object Name -eq $Member
        if (-not $d) { throw "Unknown member '$Member'. Run 'list' to see available members." }
        return @($d)
    }
    throw 'Specify -Member <name> or -All.'
}

# ---- Commands ---------------------------------------------------------------

function Invoke-List {
    $cfg = Get-Config
    Write-Host ''
    Write-Host '  Command Center — managed members' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor DarkGray
    foreach ($d in $Registry) {
        $memberCfg = Get-MemberConfig $cfg $d.Name
        $ver = if ($d.Version) { "v$($d.Version)" } else { '-' }
        $cfgState = if ($d.RequiredConfig.Count -eq 0) { 'no config needed' }
                    elseif (Test-ConfigComplete $d $memberCfg) { 'config present' }
                    else { "config MISSING ($($d.RequiredConfig -join ', '))" }
        Write-Host ("  {0,-28} {1,-8} {2}" -f $d.Name, $ver, $cfgState)
    }
    Write-Host ''
    Write-Host "  Config file: $ConfigPath" -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Status {
    $manifest = Get-Manifest
    Write-Host ''
    Write-Host '  Command Center — install status' -ForegroundColor Cyan
    Write-Host '  ----------------------------------------' -ForegroundColor DarkGray
    Write-Host ("  {0,-28} {1,-12} {2,-12} {3}" -f 'MEMBER', 'MANIFEST', 'DETECTED', 'VERSION')
    foreach ($d in $Registry) {
        $entry = Get-Entry $manifest $d.Name
        $recorded = if ($entry -and $entry.installed) { 'installed' } else { 'not-installed' }
        $detected = try { if (& $d.Detect $entry) { 'installed' } else { 'not-installed' } }
                    catch { 'unknown' }
        $ver = if ($d.Version) { "v$($d.Version)" } else { '-' }
        $color = if ($recorded -eq $detected) { 'Gray' }
                 elseif ($detected -eq 'installed') { 'Yellow' } else { 'Red' }
        Write-Host ("  {0,-28} {1,-12} {2,-12} {3}" -f $d.Name, $recorded, $detected, $ver) -ForegroundColor $color

        # Multi-instance members (file-sync, statusline-hook) record an `instances` array;
        # list each as an indented sub-row of its non-empty fields, member-agnostically.
        if ($entry -and $entry.instances) {
            foreach ($inst in @($entry.instances)) {
                $fields = ($inst.PSObject.Properties | Sort-Object Name |
                    Where-Object { $null -ne $_.Value -and "$($_.Value)" -ne '' } |
                    ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
                Write-Host ("      - $fields") -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ''
    Write-Host "  Manifest: $ManifestPath" -ForegroundColor DarkGray
    Write-Host '  (Yellow = on machine but not in manifest; Red = in manifest but not detected.)' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Install {
    $targets  = Resolve-Targets
    $cfg      = Get-Config
    $manifest = Get-Manifest

    foreach ($d in $targets) {
        $memberCfg = Get-MemberConfig $cfg $d.Name

        # -All installs only members opted in via a config entry (even an empty {}). A member
        # absent from config is skipped; use `install -Member <name>` to install it with defaults.
        if ($All -and $null -eq $memberCfg) {
            Write-Host "  - skipping $($d.Name): no entry in $ConfigPath" -ForegroundColor Yellow
            Write-Host ''
            continue
        }

        if (-not (Test-ConfigComplete $d $memberCfg)) {
            $msg = "requires config keys [$($d.RequiredConfig -join ', ')] in $ConfigPath"
            if ($All) {
                Write-Host "  - skipping $($d.Name): $msg" -ForegroundColor Yellow
                Write-Host ''
                continue
            }
            throw "$($d.Name) $msg"
        }

        Write-Host "  == installing $($d.Name) ==" -ForegroundColor Cyan
        try {
            $params = & $d.Install $d.SetupScript $memberCfg
        } catch {
            Write-Host "  ! $($d.Name) install failed: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $entry = [pscustomobject]@{
            installed    = $true
            installed_at = (Get-Date).ToString('o')
            version      = $d.Version
        }
        foreach ($k in $params.Keys) {
            $entry | Add-Member -NotePropertyName $k -NotePropertyValue $params[$k] -Force
        }
        Set-Entry $manifest $d.Name $entry
        Save-Manifest $manifest
        Write-Host "  recorded $($d.Name) in manifest" -ForegroundColor Green
        Write-Host ''
    }
}

function Invoke-Uninstall {
    $targets  = Resolve-Targets
    $manifest = Get-Manifest

    foreach ($d in $targets) {
        $entry = Get-Entry $manifest $d.Name
        Write-Host "  == uninstalling $($d.Name) ==" -ForegroundColor Cyan
        try {
            & $d.Uninstall $d.SetupScript $entry
        } catch {
            Write-Host "  ! $($d.Name) uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        Set-Entry $manifest $d.Name ([pscustomobject]@{
            installed      = $false
            uninstalled_at = (Get-Date).ToString('o')
        })
        Save-Manifest $manifest
        Write-Host "  cleared $($d.Name) in manifest" -ForegroundColor Green
        Write-Host ''
    }
}

switch ($Command) {
    'list'      { Invoke-List }
    'status'    { Invoke-Status }
    'install'   { Invoke-Install }
    'uninstall' { Invoke-Uninstall }
}
