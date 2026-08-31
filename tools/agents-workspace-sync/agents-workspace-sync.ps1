# agents-workspace-sync.ps1
#
# Commits and pushes a list of `.agents_workspace` git repos, once per run.
#
# Each configured path must be a git repo *in its own right* (its own .git). That
# is enforced, not assumed: a path that merely sits inside some outer repo is
# reported as an error and skipped. Without that guard `git -C <path> add -A`
# would walk up to the outer .git and stage the whole parent project - committing
# and pushing unrelated work-in-progress on every unattended run.
#
# Never switches branches: each repo is committed and pushed on whatever branch is
# checked out. These repos are typically sibling branches of one shared remote
# (one branch per parent project), so merging to a default branch would be wrong.
#
# Parameters:
#   -ConfigFile  Path to the JSON config. Default: agents-workspace-sync-config.json
#                next to this script, else under $C4_CLAUDE_META_DIR\.claude\scripts\.
#   -Repos       One or more repo paths, bypassing the config file (for testing).
#   -DryRun      Log what would happen; make no commit and no push.
#
# Exit codes: 0 = all repos synced, 1 = fatal (no meta dir / no config / no repos),
#             2 = ran, but one or more repos failed.

param(
    [string]$ConfigFile,
    [string[]]$Repos,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

$Tag     = "[agents-workspace-sync]"
$LogFile = $null

function Log {
    param([string]$Msg)
    $line = "[{0}] {1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $script:Tag, $Msg
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

# ---------------------------------------------------------------------------
# Logging - shares the claude-meta logs/<yyyy>/<MM>/ layout with the digests
# ---------------------------------------------------------------------------
$MetaDir = $env:C4_CLAUDE_META_DIR
if (-not $MetaDir) {
    Write-Output "$Tag C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
}

$LogStamp = Get-Date
$LogDir   = Join-Path $MetaDir ("logs\{0}\{1}" -f $LogStamp.ToString("yyyy"), $LogStamp.ToString("MM"))
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("{0}_agents-workspace-sync.log" -f $LogStamp.ToString("yyyyMMdd_HHmmss"))

# Unattended runs must never block on a credential or passphrase prompt - fail the
# push instead, so the log says so and the next run retries.
if (-not $env:GIT_TERMINAL_PROMPT) { $env:GIT_TERMINAL_PROMPT = "0" }
if (-not $env:GIT_SSH_COMMAND)     { $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes" }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
if (-not $Repos) {
    if (-not $ConfigFile) {
        $LocalCfg   = Join-Path $PSScriptRoot "agents-workspace-sync-config.json"
        $ConfigFile = if (Test-Path $LocalCfg) { $LocalCfg }
                      else { Join-Path $MetaDir ".claude\scripts\agents-workspace-sync-config.json" }
    }
    if (-not (Test-Path $ConfigFile)) {
        Log "ERROR: config not found: $ConfigFile"
        Log "       Re-run agents-workspace-sync-setup.ps1, or pass -Repos."
        exit 1
    }
    try {
        $Cfg   = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $Repos = @($Cfg.repos)
    } catch {
        Log "ERROR: could not parse $ConfigFile - $($_.Exception.Message)"
        exit 1
    }
    Log "Config: $ConfigFile"
}

$Repos = @($Repos | Where-Object { $_ -and $_.Trim() })
if (-not $Repos) {
    Log "ERROR: no repos configured - nothing to do."
    exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The configured path is expected to be the .agents_workspace repo itself. A
# parent-project path is also accepted when it contains one, so both spellings of
# the same intent work.
function Resolve-Target {
    param([string]$Raw)
    $P = $Raw.Trim().TrimEnd('\', '/')
    if (Test-Path (Join-Path $P ".git")) { return $P }
    $Nested = Join-Path $P ".agents_workspace"
    if ((Split-Path -Leaf $P) -ne ".agents_workspace" -and (Test-Path (Join-Path $Nested ".git"))) {
        return $Nested
    }
    return $P
}

# Sync one repo, incrementing $script:Failed on a logged failure.
#
# Deliberately returns nothing: Log writes to the success stream, so anything this
# function "returned" would arrive mixed into the log lines it emitted - and a
# caller testing that value would be testing a non-empty array, never the result.
function Sync-Repo {
    param([string]$Raw)

    $Repo = Resolve-Target $Raw
    # Label by the parent project - ".agents_workspace" alone identifies nothing.
    $Name = Split-Path -Leaf (Split-Path -Parent $Repo)

    if (-not (Test-Path $Repo)) {
        Log "ERROR [$Raw]: path does not exist."
        $script:Failed++; return
    }

    # The guard: the path must be the top level of its own repo, not a directory
    # inside an outer one.
    #
    # --show-prefix is the cwd's path relative to the repo root, so it is empty
    # exactly at a root. Comparing paths textually instead would be wrong - git
    # reports "C:/x/y" where Git Bash's pwd reports "/c/x/y", and case, symlinks
    # and 8.3 short names all differ too.
    $Prefix = git -C $Repo rev-parse --show-prefix 2>$null
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR [$Repo]: not a git repo."
        $script:Failed++; return
    }
    if ($Prefix) {
        $Top = git -C $Repo rev-parse --show-toplevel 2>$null
        Log "ERROR [$Repo]: not a git repo by itself - it belongs to $Top. Skipping (staging here would commit the parent repo)."
        $script:Failed++; return
    }

    $Branch = git -C $Repo branch --show-current 2>$null
    if (-not $Branch) {
        Log "ERROR [$Name]: detached HEAD - skipping."
        $script:Failed++; return
    }

    if ($DryRun) {
        $Dirty = git -C $Repo status --porcelain 2>$null
        $What  = if ($Dirty) { "$(@($Dirty).Count) change(s)" } else { "no changes" }
        Log "DRY-RUN [$Name] branch $Branch - $What."
        return
    }

    git -C $Repo add -A
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR [$Name]: git add failed (exit $LASTEXITCODE)."
        $script:Failed++; return
    }

    $Staged = git -C $Repo diff --cached --name-only 2>$null
    if ($Staged) {
        $Message = "agents-workspace-sync: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm")
        git -C $Repo commit -q -m $Message
        if ($LASTEXITCODE -ne 0) {
            Log "ERROR [$Name]: commit failed (exit $LASTEXITCODE)."
            $script:Failed++; return
        }
        Log "[$Name] Committed $(@($Staged).Count) file(s) on $Branch."
    } else {
        Log "[$Name] Nothing to commit."
    }

    $Remote = git -C $Repo remote 2>$null
    if (-not $Remote) {
        Log "[$Name] No remote configured - commit only."
        return
    }

    git -C $Repo rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null | Out-Null
    $HasUpstream = ($LASTEXITCODE -eq 0)

    if ($HasUpstream) {
        $Ahead = git -C $Repo rev-list --count "@{u}..HEAD" 2>$null
        if ($LASTEXITCODE -ne 0 -or [int]$Ahead -eq 0) {
            Log "[$Name] Up to date with upstream - nothing to push."
            return
        }
        git -C $Repo push
        if ($LASTEXITCODE -ne 0) {
            Log "ERROR [$Name]: push failed (exit $LASTEXITCODE)."
            $script:Failed++; return
        }
        Log "[$Name] Pushed $Ahead commit(s) to $Branch."
    } else {
        # First push of this branch - publish it and set tracking.
        $Origin = @($Remote)[0]
        git -C $Repo push -u $Origin $Branch
        if ($LASTEXITCODE -ne 0) {
            Log "ERROR [$Name]: push failed (exit $LASTEXITCODE)."
            $script:Failed++; return
        }
        Log "[$Name] Pushed and set upstream $Origin/$Branch."
    }

    return
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
$Mode = if ($DryRun) { " (dry run)" } else { "" }
Log "Start - $($Repos.Count) repo(s)$Mode."

$Failed = 0
foreach ($R in $Repos) {
    Sync-Repo $R
}

if ($Failed -gt 0) {
    Log "Done - $($Repos.Count - $Failed) ok, $Failed failed. Log: $LogFile"
    exit 2
}

Log "Done - all $($Repos.Count) repo(s) ok. Log: $LogFile"
exit 0
