#!/usr/bin/env bash
# git-sync.sh
# Stages all changes in claude-meta, commits with a timestamped message, and pushes.
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

git add -A

STAGED=$(git diff --cached --name-only 2>/dev/null || true)
if [[ -z "$STAGED" ]]; then
    log "[git-sync] Nothing to commit."
    exit 0
fi

TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
MESSAGE="${LABEL}: ${TIMESTAMP}"

git commit -m "$MESSAGE"
log "[git-sync] Committed: $MESSAGE"

REMOTE=$(git remote 2>/dev/null || true)
if [[ -n "$REMOTE" ]]; then
    git push
    log "[git-sync] Pushed."
else
    log "[git-sync] No remote configured - commit only."
fi
