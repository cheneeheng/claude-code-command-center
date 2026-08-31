#!/usr/bin/env bash
# agents-workspace-sync.sh
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
# Usage: ./agents-workspace-sync.sh [--config <file>] [--dry-run] [repo ...]
#   --config   JSON config. Default: agents-workspace-sync-config.json next to this
#              script, else $C4_CLAUDE_META_DIR/.claude/scripts/.
#   --dry-run  Log what would happen; make no commit and no push.
#   repo ...   Repo paths, bypassing the config file (for testing).
#
# Exit codes: 0 = all repos synced, 1 = fatal (no meta dir / no config / no repos),
#             2 = ran, but one or more repos failed.

set -uo pipefail

TAG="[agents-workspace-sync]"
LOG_FILE=""

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $TAG $*"
    printf '%s\n' "$line"
    [[ -n "$LOG_FILE" ]] && printf '%s\n' "$line" >> "$LOG_FILE"
    return 0
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
CONFIG_FILE=""
DRY_RUN=""
REPOS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *)         REPOS+=("$1"); shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging - shares the claude-meta logs/<yyyy>/<MM>/ layout with the digests
# ---------------------------------------------------------------------------
META_DIR="${C4_CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    printf '%s\n' "$TAG C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
fi

LOG_STAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_DIR="$META_DIR/logs/${LOG_STAMP:0:4}/${LOG_STAMP:4:2}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${LOG_STAMP}_agents-workspace-sync.log"

# Unattended runs must never block on a credential or passphrase prompt - fail the
# push instead, so the log says so and the next run retries.
export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
if [[ ${#REPOS[@]} -eq 0 ]]; then
    if [[ -z "$CONFIG_FILE" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$SCRIPT_DIR/agents-workspace-sync-config.json" ]]; then
            CONFIG_FILE="$SCRIPT_DIR/agents-workspace-sync-config.json"
        else
            CONFIG_FILE="$META_DIR/.claude/scripts/agents-workspace-sync-config.json"
        fi
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR: config not found: $CONFIG_FILE"
        log "       Re-run agents-workspace-sync-setup.sh, or pass repo paths."
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR: jq is required to read $CONFIG_FILE."
        exit 1
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && REPOS+=("$line")
    done < <(jq -r '.repos[]? // empty' "$CONFIG_FILE")
    log "Config: $CONFIG_FILE"
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
    log "ERROR: no repos configured - nothing to do."
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The configured path is expected to be the .agents_workspace repo itself. A
# parent-project path is also accepted when it contains one, so both spellings of
# the same intent work.
resolve_target() {
    local p="${1%/}"
    if [[ -e "$p/.git" ]]; then printf '%s\n' "$p"; return; fi
    if [[ "$(basename "$p")" != ".agents_workspace" && -e "$p/.agents_workspace/.git" ]]; then
        printf '%s\n' "$p/.agents_workspace"; return
    fi
    printf '%s\n' "$p"
}

# Sync one repo. Returns 0 on success, 1 on a logged failure.
sync_repo() {
    local raw="$1"
    local repo name top prefix branch staged ahead remote origin
    repo="$(resolve_target "$raw")"
    # Label by the parent project - ".agents_workspace" alone identifies nothing.
    name="$(basename "$(dirname "$repo")")"

    if [[ ! -d "$repo" ]]; then
        log "ERROR [$raw]: path does not exist."
        return 1
    fi

    # The guard: the path must be the top level of its own repo, not a directory
    # inside an outer one.
    #
    # --show-prefix is the cwd's path relative to the repo root, so it is empty
    # exactly at a root. Comparing paths textually instead would be wrong - git
    # reports "C:/x/y" where Git Bash's pwd reports "/c/x/y", and case, symlinks
    # and 8.3 short names all differ too.
    if ! prefix="$(git -C "$repo" rev-parse --show-prefix 2>/dev/null)"; then
        log "ERROR [$repo]: not a git repo."
        return 1
    fi
    if [[ -n "$prefix" ]]; then
        top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
        log "ERROR [$repo]: not a git repo by itself - it belongs to $top. Skipping (staging here would commit the parent repo)."
        return 1
    fi

    branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    if [[ -z "$branch" ]]; then
        log "ERROR [$name]: detached HEAD - skipping."
        return 1
    fi

    if [[ -n "$DRY_RUN" ]]; then
        local dirty count what
        dirty="$(git -C "$repo" status --porcelain 2>/dev/null)"
        if [[ -n "$dirty" ]]; then
            count="$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')"
            what="$count change(s)"
        else
            what="no changes"
        fi
        log "DRY-RUN [$name] branch $branch - $what."
        return 0
    fi

    if ! git -C "$repo" add -A; then
        log "ERROR [$name]: git add failed."
        return 1
    fi

    staged="$(git -C "$repo" diff --cached --name-only 2>/dev/null)"
    if [[ -n "$staged" ]]; then
        if ! git -C "$repo" commit -q -m "agents-workspace-sync: $(date '+%Y-%m-%d %H:%M')"; then
            log "ERROR [$name]: commit failed."
            return 1
        fi
        log "[$name] Committed $(printf '%s\n' "$staged" | wc -l | tr -d ' ') file(s) on $branch."
    else
        log "[$name] Nothing to commit."
    fi

    remote="$(git -C "$repo" remote 2>/dev/null | head -1)"
    if [[ -z "$remote" ]]; then
        log "[$name] No remote configured - commit only."
        return 0
    fi

    if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        ahead="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
        if [[ "$ahead" -eq 0 ]]; then
            log "[$name] Up to date with upstream - nothing to push."
            return 0
        fi
        if ! git -C "$repo" push; then
            log "ERROR [$name]: push failed."
            return 1
        fi
        log "[$name] Pushed $ahead commit(s) to $branch."
    else
        # First push of this branch - publish it and set tracking.
        origin="$remote"
        if ! git -C "$repo" push -u "$origin" "$branch"; then
            log "ERROR [$name]: push failed."
            return 1
        fi
        log "[$name] Pushed and set upstream $origin/$branch."
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
MODE=""
[[ -n "$DRY_RUN" ]] && MODE=" (dry run)"
log "Start - ${#REPOS[@]} repo(s)${MODE}."

FAILED=0
for r in "${REPOS[@]}"; do
    sync_repo "$r" || FAILED=$((FAILED + 1))
done

if [[ $FAILED -gt 0 ]]; then
    log "Done - $(( ${#REPOS[@]} - FAILED )) ok, $FAILED failed. Log: $LOG_FILE"
    exit 2
fi

log "Done - all ${#REPOS[@]} repo(s) ok. Log: $LOG_FILE"
exit 0
