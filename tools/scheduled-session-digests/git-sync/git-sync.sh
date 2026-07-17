#!/usr/bin/env bash
# git-sync.sh
# Stages all changes in claude-meta, commits with a timestamped message, merges the
# current branch back into the default branch if they differ, and pushes.
# Called by scheduler trigger scripts after Claude writes output files.
#
# Usage: ./git-sync.sh [label]
#   label: included in the commit message (default: "auto")

set -euo pipefail

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$line"
    [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >> "$LOG_FILE"
}

LABEL="${1:-auto}"
META_DIR="${C4_CLAUDE_META_DIR:-}"

if [[ -z "$META_DIR" ]]; then
    log "[git-sync] C4_CLAUDE_META_DIR is not set - skipping."
    exit 0
fi

LOG_DIR="$META_DIR/logs"
mkdir -p "$LOG_DIR"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCRIPT_NAME}.log"

if [[ ! -d "$META_DIR/.git" ]]; then
    log "[git-sync] $META_DIR is not a git repo - skipping."
    echo "           Run 'git init' in $META_DIR, or re-run install.sh to initialise it."
    exit 0
fi

cd "$META_DIR"

# Run logs (including this script's own) keep being written after the push, so
# tracking them would leave the tree dirty after every run - keep them local-only.
GITIGNORE="$META_DIR/.gitignore"
if ! grep -qxF "/logs/" "$GITIGNORE" 2>/dev/null; then
    echo "/logs/" >> "$GITIGNORE"
fi
git rm -r --cached --ignore-unmatch --quiet logs

git add -A

STAGED=$(git diff --cached --name-only 2>/dev/null || true)

# Interactive skill runs can start on a feature branch (a branch guard may force
# one before Claude writes files); merge it back so digests always land on the
# default branch.
BRANCH=$(git branch --show-current)
DEFAULT=""
if git show-ref --verify --quiet refs/heads/main; then
    DEFAULT="main"
elif git show-ref --verify --quiet refs/heads/master; then
    DEFAULT="master"
fi
NEEDS_MERGE=""
[[ -n "$DEFAULT" && -n "$BRANCH" && "$BRANCH" != "$DEFAULT" ]] && NEEDS_MERGE=1

if [[ -z "$STAGED" && -z "$NEEDS_MERGE" ]]; then
    log "[git-sync] Nothing to commit."
    exit 0
fi

if [[ -n "$STAGED" ]]; then
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
    MESSAGE="${LABEL}: ${TIMESTAMP}"

    git commit -m "$MESSAGE"
    log "[git-sync] Committed: $MESSAGE"
else
    log "[git-sync] Nothing to commit."
fi

MERGED=""
if [[ -n "$NEEDS_MERGE" ]]; then
    git checkout --quiet "$DEFAULT"
    if git merge --quiet "$BRANCH"; then
        git branch --quiet -d "$BRANCH"
        MERGED=1
        log "[git-sync] Merged $BRANCH into $DEFAULT and deleted the branch."
    else
        [[ -f "$META_DIR/.git/MERGE_HEAD" ]] && git merge --abort
        git checkout --quiet "$BRANCH"
        log "[git-sync] WARNING: could not merge $BRANCH into $DEFAULT - resolve manually."
    fi
fi

REMOTE=$(git remote 2>/dev/null || true)
if [[ -n "$REMOTE" ]]; then
    if git push; then
        log "[git-sync] Pushed."
    else
        log "[git-sync] WARNING: push failed."
    fi
    # The merged branch may have been pushed by an earlier run; drop the stale copy.
    if [[ -n "$MERGED" ]] && [[ -n "$(git ls-remote --heads origin "$BRANCH")" ]]; then
        git push --quiet origin --delete "$BRANCH"
    fi
else
    log "[git-sync] No remote configured - commit only."
fi
