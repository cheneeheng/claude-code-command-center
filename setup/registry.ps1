#!/usr/bin/env pwsh
# Catalog of the installable tools/ members the command-center orchestrator manages.
# Dot-source this and call Get-CommandCenterRegistry -RepoRoot <repo root>.
#
# Each descriptor is a [pscustomobject] with:
#   Name           - member folder name / manifest key
#   DisplayName    - human label
#   Category       - 'tools'
#   SetupScript    - absolute path to the member's own install/uninstall script
#   Version        - version string (VERSION file or pyproject), or $null
#   RequiredConfig - config keys that must be present for an unattended (-All) install
#   Install        - { param($SetupScript, $Config)  -> returns params hashtable to record }
#   Uninstall      - { param($SetupScript, $Entry)   -> reverses, using recorded params }
#   Detect         - { param($Entry) -> [bool] real, on-machine install state }

function Read-MemberVersion([string]$Dir) {
    $versionFile = Join-Path $Dir 'VERSION'
    if (Test-Path $versionFile) { return (Get-Content -Raw $versionFile).Trim() }
    $pyproject = Join-Path $Dir 'pyproject.toml'
    if (Test-Path $pyproject) {
        $m = Select-String -Path $pyproject -Pattern '^\s*version\s*=\s*"([^"]+)"' | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return $null
}

function Get-CommandCenterRegistry {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $tools = Join-Path $RepoRoot 'tools'

    # --- session-name-date-prefixer ------------------------------------------
    $snpDir = Join-Path $tools 'session-name-date-prefixer'
    $sessionNamePrefixer = [pscustomobject]@{
        Name           = 'session-name-date-prefixer'
        DisplayName    = 'Session name date prefixer'
        Category       = 'tools'
        SetupScript    = Join-Path $snpDir 'session-name-date-prefixer-setup.ps1'
        Version        = Read-MemberVersion $snpDir
        RequiredConfig = @()
        Install        = { param($SetupScript, $Config) & $SetupScript -Action install | Out-Null; @{} }
        Uninstall      = { param($SetupScript, $Entry)  & $SetupScript -Action uninstall | Out-Null }
        Detect         = {
            param($Entry)
            $bin = Join-Path $env:LOCALAPPDATA 'claude-automation\cc-inject-date-to-session-name'
            Test-Path (Join-Path $bin 'claude.ps1')
        }
    }

    # --- statusline-hook -----------------------------------------------------
    $slDir = Join-Path $tools 'statusline-hook'
    $statuslineHook = [pscustomobject]@{
        Name           = 'statusline-hook'
        DisplayName    = 'Status line hook'
        Category       = 'tools'
        SetupScript    = Join-Path $slDir 'statusline-hook-setup.ps1'
        Version        = Read-MemberVersion $slDir
        RequiredConfig = @()
        Install        = {
            param($SetupScript, $Config)
            $variant = if ($Config -and $Config.variant) { $Config.variant } else { 'ps1' }
            & $SetupScript -Action install -Variant $variant | Out-Null
            @{ variant = $variant }
        }
        Uninstall      = { param($SetupScript, $Entry) & $SetupScript -Action uninstall | Out-Null }
        Detect         = {
            param($Entry)
            $dir = if ($env:CLAUDE_DIR) { ($env:CLAUDE_DIR -split [IO.Path]::PathSeparator)[0] }
                   else { Join-Path $env:USERPROFILE '.claude' }
            $settings = Join-Path $dir 'settings.json'
            if (Test-Path $settings) {
                $raw = Get-Content -Raw $settings
                if ($raw.Trim()) {
                    return (($raw | ConvertFrom-Json).PSObject.Properties.Name -contains 'statusLine')
                }
            }
            $false
        }
    }

    # --- file-sync -----------------------------------------------------------
    $fsDir = Join-Path $tools 'file-sync'
    $fileSync = [pscustomobject]@{
        Name           = 'file-sync'
        DisplayName    = 'File sync (CLAUDE.md / settings.json)'
        Category       = 'tools'
        SetupScript    = Join-Path $fsDir 'sync-setup.ps1'
        Version        = Read-MemberVersion $fsDir
        RequiredConfig = @('instances')   # no sensible default folder pair exists
        Install        = {
            param($SetupScript, $Config)
            if (-not $Config -or -not $Config.instances) {
                throw "file-sync needs an 'instances' array in config (folder pairs to sync)."
            }
            $used = @()
            foreach ($i in $Config.instances) {
                $splat = @{
                    Action          = 'install'
                    FileName        = $i.fileName
                    FolderA         = $i.folderA
                    FolderB         = $i.folderB
                    Strategy        = if ($i.strategy) { $i.strategy } else { 'raw' }
                    IntervalMinutes = if ($i.intervalMinutes) { $i.intervalMinutes } else { 15 }
                }
                if ($i.PSObject.Properties.Name -contains 'excludePaths' -and $i.excludePaths) {
                    $splat.ExcludePaths = $i.excludePaths
                }
                & $SetupScript @splat | Out-Null
                $used += @{
                    fileName        = $i.fileName
                    folderA         = $i.folderA
                    folderB         = $i.folderB
                    strategy        = $splat.Strategy
                    intervalMinutes = $splat.IntervalMinutes
                    excludePaths    = $i.excludePaths
                }
            }
            @{ instances = $used }
        }
        Uninstall      = {
            param($SetupScript, $Entry)
            foreach ($i in @($Entry.instances)) {
                & $SetupScript -Action uninstall -FileName $i.fileName -FolderA $i.folderA -FolderB $i.folderB | Out-Null
            }
        }
        Detect         = {
            param($Entry)
            [bool](Get-ScheduledTask -TaskPath '\file-sync\' -ErrorAction SilentlyContinue)
        }
    }

    # --- scheduled-session-digests -------------------------------------------
    $sdDir = Join-Path $tools 'scheduled-session-digests'
    $sessionDigests = [pscustomobject]@{
        Name           = 'scheduled-session-digests'
        DisplayName    = 'Scheduled session digests'
        Category       = 'tools'
        SetupScript    = Join-Path $sdDir 'setup.ps1'
        Version        = Read-MemberVersion $sdDir
        RequiredConfig = @()   # defaults to skill-based digests under ~/claude-meta
        Install        = {
            param($SetupScript, $Config)
            $meta  = if ($Config -and $Config.metaDir) { $Config.metaDir }
                     else { Join-Path $env:USERPROFILE 'claude-meta' }
            $picks = if ($Config -and $Config.picks) { @($Config.picks) }
                     else { @('ds-skill', 'dl-skill', 'wl-skill') }
            & $SetupScript -NonInteractive -Action install -MetaDir $meta -Picks $picks | Out-Null
            @{ metaDir = $meta; picks = $picks }
        }
        Uninstall      = {
            param($SetupScript, $Entry)
            $meta = if ($Entry -and $Entry.metaDir) { $Entry.metaDir } else { $env:CLAUDE_META_DIR }
            if ($meta) { & $SetupScript -NonInteractive -Action uninstall -MetaDir $meta | Out-Null }
            else       { & $SetupScript -NonInteractive -Action uninstall | Out-Null }
        }
        Detect         = {
            param($Entry)
            foreach ($task in 'SessionDigest-DailySummary', 'SessionDigest-DailyLessons', 'SessionDigest-WeeklyLessons') {
                if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { return $true }
            }
            $meta = $env:CLAUDE_META_DIR
            if (-not $meta -and $Entry) { $meta = $Entry.metaDir }
            if ($meta) {
                $scripts = Join-Path $meta '.claude\scripts'
                if (Test-Path $scripts) {
                    if (Get-ChildItem $scripts -Filter '*-prepare.ps1' -ErrorAction SilentlyContinue) { return $true }
                    if (Get-ChildItem $scripts -Filter '*-trigger.ps1' -ErrorAction SilentlyContinue) { return $true }
                }
            }
            $false
        }
    }

    @($sessionNamePrefixer, $statuslineHook, $fileSync, $sessionDigests)
}
