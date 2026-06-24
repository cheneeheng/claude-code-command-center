#!/usr/bin/env bash
# weekly-lessons-trigger.sh
#
# Triggered by cron every Sunday at 02:00.
# Scans $CLAUDE_META_DIR/lessons-learned/**/*.md for files written since the
# last harvest, skips stub files, and passes the collected content to Claude
# for analysis and master-file update.
#
# Time filtering: a cursor file ($CLAUDE_META_DIR/.claude/weekly-lessons-cursor)
# records the mtime (Unix epoch) of the newest lessons file processed on the
# last successful run. Only files newer than the cursor are processed.
# The cursor is updated only after Claude exits successfully, so a crash causes
# the same files to be retried on the next run.
#
# Dependencies: bash 4+, git, claude CLI
#
# Cron setup (done by install.sh, or manually):
#   0 2 * * 0 /path/to/weekly-lessons-trigger.sh

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

# Source env file if CLAUDE_META_DIR is not already set (needed for cron)
ENV_FILE="$HOME/.claude/claude-scheduler.env"
if [[ -z "${CLAUDE_META_DIR:-}" ]] && [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

META_DIR="${CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    log "[weekly-lessons] CLAUDE_META_DIR is not set - aborting."
    exit 1
fi

LOG_DIR="$META_DIR/logs"
mkdir -p "$LOG_DIR"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCRIPT_NAME}.log"

LESSONS_BASE="$META_DIR/lessons-learned"
CURSOR_FILE="$META_DIR/.claude/weekly-lessons-cursor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/weekly-lessons.md"
INPUT_FILE="$SCRIPT_DIR/weekly-lessons-input.md"
GIT_SYNC="$SCRIPT_DIR/git-sync.sh"
DATE=$(date +"%Y-%m-%d")

# Guard: prompt file must be installed alongside this script
if [[ ! -f "$PROMPT_FILE" ]]; then
    log "[weekly-lessons] Prompt file not found at $PROMPT_FILE - run install.sh first."
    exit 1
fi
if [[ ! -f "$GIT_SYNC" ]]; then
    log "[weekly-lessons] git-sync.sh not found at $GIT_SYNC - run install.sh first."
    exit 1
fi

# Guard: lessons-learned directory must exist
if [[ ! -d "$LESSONS_BASE" ]]; then
    log "[weekly-lessons] lessons-learned directory not found at $LESSONS_BASE - has daily-lessons run yet?"
    exit 0
fi

# Cleanup input file on exit (crash or normal)
cleanup() { rm -f "$INPUT_FILE"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Determine cutoff from cursor file
# ---------------------------------------------------------------------------
if [[ "$FULL_SCAN" == true ]]; then
    log "[weekly-lessons] Full scan requested - processing all lessons files."
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (full scan)"
elif [[ -f "$CURSOR_FILE" ]]; then
    CUTOFF_EPOCH=$(cat "$CURSOR_FILE" | tr -d '[:space:]')
    if ! [[ "$CUTOFF_EPOCH" =~ ^[0-9]+$ ]]; then
        log "[weekly-lessons] WARNING: cursor file unreadable - treating as first run."
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
    log "[weekly-lessons] No new lessons files since $CUTOFF_LABEL - skipping."
    exit 0
fi

log "[weekly-lessons] Found ${#LESSONS_FILES[@]} new lessons file(s) since $CUTOFF_LABEL."

# ---------------------------------------------------------------------------
# Build harvest input file for Claude
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

log "[weekly-lessons] Collected ${#LESSONS_FILES[@]} file(s). Passing to Claude..."

# ---------------------------------------------------------------------------
# Run Claude for analysis and master-file update
# ---------------------------------------------------------------------------
PROMPT=$(cat "$PROMPT_FILE")

cd "$META_DIR"
claude --print "$PROMPT"

# Update cursor to the newest processed file's mtime - only reached on success
# (set -euo pipefail exits on non-zero above), so a crash skips this and the
# same files are retried next run.
LATEST_IDX=$(( ${#LESSONS_FILES[@]} - 1 ))
LATEST_FILE="${LESSONS_FILES[$LATEST_IDX]}"
NEW_EPOCH=$(stat --format="%Y" "$LATEST_FILE" 2>/dev/null || stat -f "%m" "$LATEST_FILE" 2>/dev/null || echo 0)
echo "$NEW_EPOCH" > "$CURSOR_FILE"
CURSOR_DATE=$(date -d "@$NEW_EPOCH" +"%Y-%m-%d %H:%M" 2>/dev/null || date -r "$NEW_EPOCH" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "epoch $NEW_EPOCH")
log "[weekly-lessons] Cursor updated to $CURSOR_DATE."

# Input file is removed by the cleanup trap on exit.
bash "$GIT_SYNC" "weekly-lessons"

log "[weekly-lessons] Done. Check $META_DIR/master-lessons/ for updates."
