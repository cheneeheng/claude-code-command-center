#!/usr/bin/env bash
# weekly-lessons-prepare.sh
#
# Interactive-session variant of weekly-lessons-trigger.sh. Does everything the
# trigger does EXCEPT calling `claude --print`, updating the cursor, and git-sync.
# It scans lessons-learned for files written since the last harvest, skips stubs,
# and writes the collected content to an input file. The /weekly-lessons skill
# (running inside an interactive Claude Code session) then reads that input plus
# the master file, updates the master, advances the cursor, and commits.
#
# Output (printed for the skill to consume):
#   INPUT=<harvest input file>
#   FILES=<number of source lessons files>
#   LATEST_EPOCH=<mtime of newest source file; write to CURSOR after success>
#   CURSOR=<cursor file path>
#   MASTER=<master lessons file path>
#
# Dependencies: bash 4+, git
#
# Usage (normally invoked by the /weekly-lessons skill):
#   CLAUDE_META_DIR=/path/to/claude-meta ./weekly-lessons-prepare.sh [--full-scan]

set -euo pipefail

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$line"
    [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >> "$LOG_FILE"
}

FULL_SCAN=false
for arg in "$@"; do
    case "$arg" in
        --full-scan) FULL_SCAN=true ;;
    esac
done

# Source env file if CLAUDE_META_DIR is not already set
ENV_FILE="$HOME/.claude/claude-scheduler.env"
if [[ -z "${CLAUDE_META_DIR:-}" ]] && [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

META_DIR="${CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    log "[weekly-lessons-prepare] CLAUDE_META_DIR is not set - aborting."
    exit 1
fi

LOG_DIR="$META_DIR/logs"
mkdir -p "$LOG_DIR"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCRIPT_NAME}.log"

LESSONS_BASE="$META_DIR/lessons-learned"
CURSOR_FILE="$META_DIR/.claude/weekly-lessons-cursor"
MASTER_FILE="$META_DIR/master-lessons/MASTER_LESSONS_LEARNED.md"
JOBS_DIR="$META_DIR/.claude/scheduler-jobs/weekly-lessons"
INPUT_FILE="$JOBS_DIR/input.md"
DATE=$(date +"%Y-%m-%d")

# Keep the transient staging area out of git so it is never committed.
GITIGNORE="$META_DIR/.gitignore"
if ! grep -q "^.claude/scheduler-jobs/" "$GITIGNORE" 2>/dev/null; then
    echo ".claude/scheduler-jobs/" >> "$GITIGNORE"
fi

rm -rf "$JOBS_DIR"
mkdir -p "$JOBS_DIR"

# Guard: lessons-learned directory must exist
if [[ ! -d "$LESSONS_BASE" ]]; then
    log "[weekly-lessons-prepare] lessons-learned directory not found at $LESSONS_BASE - has daily-lessons run yet?"
    echo "FILES=0"
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine cutoff from cursor file
# ---------------------------------------------------------------------------
if [[ "$FULL_SCAN" == true ]]; then
    log "[weekly-lessons-prepare] Full scan requested - processing all lessons files."
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (full scan)"
elif [[ -f "$CURSOR_FILE" ]]; then
    CUTOFF_EPOCH=$(cat "$CURSOR_FILE" | tr -d '[:space:]')
    if ! [[ "$CUTOFF_EPOCH" =~ ^[0-9]+$ ]]; then
        log "[weekly-lessons-prepare] WARNING: cursor file unreadable - treating as first run."
        CUTOFF_EPOCH=0
        CUTOFF_LABEL="beginning of time (cursor reset)"
    else
        CUTOFF_LABEL=$(date -d "@$CUTOFF_EPOCH" +"%Y-%m-%d %H:%M" 2>/dev/null || date -r "$CUTOFF_EPOCH" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "epoch $CUTOFF_EPOCH")
    fi
else
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (first run)"
fi

# ---------------------------------------------------------------------------
# Find lessons files written after the cutoff; skip stubs
# ---------------------------------------------------------------------------
readarray -t LESSONS_FILES < <(
    find "$LESSONS_BASE" -name "*.md" -type f 2>/dev/null |
        while IFS= read -r f; do
            mtime=$(stat --format="%Y" "$f" 2>/dev/null || stat -f "%m" "$f" 2>/dev/null || echo 0)
            [[ $mtime -gt $CUTOFF_EPOCH ]] || continue
            grep -qF '_No lessons extracted from this session._' "$f" 2>/dev/null && continue
            echo "$mtime $f"
        done |
        sort -n | awk '{print $2}'
)

if [[ ${#LESSONS_FILES[@]} -eq 0 ]]; then
    log "[weekly-lessons-prepare] No new lessons files since $CUTOFF_LABEL - nothing to prepare."
    echo "FILES=0"
    exit 0
fi

log "[weekly-lessons-prepare] Found ${#LESSONS_FILES[@]} new lessons file(s) since $CUTOFF_LABEL."

# ---------------------------------------------------------------------------
# Build harvest input file
# ---------------------------------------------------------------------------
{
    echo "# Lessons Harvest Input - $DATE"
    echo ""

    for f in "${LESSONS_FILES[@]}"; do
        rel="${f#"$LESSONS_BASE/"}"
        mtime=$(stat --format="%Y" "$f" 2>/dev/null || stat -f "%m" "$f" 2>/dev/null || echo 0)
        file_date=$(date -d "@$mtime" +"%Y-%m-%d" 2>/dev/null || date -r "$mtime" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

        echo "## Source: $rel"
        echo "Date: $file_date"
        echo ""
        cat "$f"
        echo ""
        echo ""
        echo "---"
        echo ""
    done
} > "$INPUT_FILE"

# Newest processed file's mtime - the skill writes this to the cursor on success.
LATEST_IDX=$(( ${#LESSONS_FILES[@]} - 1 ))
LATEST_FILE="${LESSONS_FILES[$LATEST_IDX]}"
LATEST_EPOCH=$(stat --format="%Y" "$LATEST_FILE" 2>/dev/null || stat -f "%m" "$LATEST_FILE" 2>/dev/null || echo 0)

log "[weekly-lessons-prepare] Collected ${#LESSONS_FILES[@]} file(s) -> $INPUT_FILE"
echo "INPUT=$INPUT_FILE"
echo "FILES=${#LESSONS_FILES[@]}"
echo "LATEST_EPOCH=$LATEST_EPOCH"
echo "CURSOR=$CURSOR_FILE"
echo "MASTER=$MASTER_FILE"
