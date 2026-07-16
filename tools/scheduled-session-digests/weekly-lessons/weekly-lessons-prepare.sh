#!/usr/bin/env bash
# weekly-lessons-prepare.sh
#
# Stages the weekly lessons harvest. Shared by both run mechanisms:
#   - cron : weekly-lessons-trigger.sh runs this, then runs `claude --print`.
#   - skill: the /session-digest-weekly-lessons skill runs this, then does the
#            harvest inline.
#
# What it does:
#   1. Reads the cursor file ($C4_CLAUDE_META_DIR/.claude/weekly-lessons-cursor,
#      Unix epoch mtime of the newest lessons file processed on the last
#      successful run) to determine the scan cutoff.
#   2. Scans lessons-learned/**/*.md (written by daily-lessons) for files newer
#      than the cutoff, skipping "no lessons" stub files.
#   3. Collects their content into input.md plus manifest.json in the staging
#      dir $C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/weekly-lessons/
#      (gitignored, reset on every run).
#
# The consumer writes cursorEpoch to the cursor file only after a successful
# harvest, so a crash retries the same files on the next run.
#
# Manifest shape:
#   { "scheduler":   "weekly-lessons",
#     "cursor":      "<cursor file path>",
#     "cursorEpoch": <epoch to write to the cursor after a successful harvest>,
#     "files":       <number of collected source files>,
#     "input":       "<staged harvest input path>",
#     "master":      "<master lessons file path>" }
#
# Dependencies: bash 4+, jq
#
# Usage:
#   weekly-lessons-prepare.sh [--full-scan]

set -euo pipefail

FULL_SCAN=false
for arg in "$@"; do
    case "$arg" in
        --full-scan) FULL_SCAN=true ;;
    esac
done

TAG="[weekly-lessons-prepare]"
log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $TAG $*"
    printf '%s\n' "$line"
    [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >> "$LOG_FILE"
}

# Source the env file if C4_CLAUDE_META_DIR is not already set (needed for cron)
ENV_FILE="$HOME/.claude/claude-scheduler.env"
if [[ -z "${C4_CLAUDE_META_DIR:-}" ]] && [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

META_DIR="${C4_CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    log "C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
fi

LOG_DIR="$META_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_weekly-lessons-prepare.log"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
LESSONS_BASE="$META_DIR/lessons-learned"
MASTER_FILE="$META_DIR/master-lessons/MASTER_LESSONS_LEARNED.md"
CURSOR_FILE="$META_DIR/.claude/weekly-lessons-cursor"
STAGING_DIR="$META_DIR/.claude/scheduled-session-digests/weekly-lessons"
INPUT_FILE="$STAGING_DIR/input.md"
MANIFEST="$STAGING_DIR/manifest.json"
DATE=$(date +"%Y-%m-%d")

# Keep the transient staging area out of git so a partial run is never committed.
GITIGNORE="$META_DIR/.gitignore"
if ! grep -qF ".claude/scheduled-session-digests/" "$GITIGNORE" 2>/dev/null; then
    echo ".claude/scheduled-session-digests/" >> "$GITIGNORE"
fi

# ---------------------------------------------------------------------------
# Reset the staging dir and write an empty manifest up front so the consumer
# always has something valid to read.
# ---------------------------------------------------------------------------
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

write_manifest() {
    # $1 = cursor epoch, $2 = number of collected files
    jq -n \
        --arg cursor "$CURSOR_FILE" \
        --argjson cursorEpoch "$1" \
        --argjson files "$2" \
        --arg input "$INPUT_FILE" \
        --arg master "$MASTER_FILE" \
        '{scheduler: "weekly-lessons", cursor: $cursor, cursorEpoch: $cursorEpoch, files: $files, input: $input, master: $master}' \
        > "$MANIFEST"
}

emit_result() {
    echo "MANIFEST=$MANIFEST"
    echo "JOBS=$1"
}

write_manifest 0 0

if [[ ! -d "$LESSONS_BASE" ]]; then
    log "lessons-learned directory not found at $LESSONS_BASE - has daily-lessons run yet?"
    emit_result 0
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine the scan cutoff from the cursor file
# ---------------------------------------------------------------------------
if [[ "$FULL_SCAN" == true ]]; then
    log "Full scan requested - processing all lessons files."
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (full scan)"
elif [[ -f "$CURSOR_FILE" ]]; then
    CUTOFF_EPOCH=$(tr -d '[:space:]' < "$CURSOR_FILE")
    if ! [[ "$CUTOFF_EPOCH" =~ ^[0-9]+$ ]]; then
        log "WARNING: cursor file unreadable - treating as first run."
        CUTOFF_EPOCH=0
        CUTOFF_LABEL="beginning of time (cursor reset)"
    else
        CUTOFF_LABEL=$(date -d "@$CUTOFF_EPOCH" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "epoch $CUTOFF_EPOCH")
    fi
else
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (first run)"
fi

# ---------------------------------------------------------------------------
# Find lessons files written after the cutoff; skip "no lessons" stubs
# ---------------------------------------------------------------------------
readarray -t LESSONS_FILES < <(
    find "$LESSONS_BASE" -name "*.md" -type f 2>/dev/null |
        while IFS= read -r f; do
            mtime=$(stat -c "%Y" "$f" 2>/dev/null || echo 0)
            [[ $mtime -gt $CUTOFF_EPOCH ]] || continue
            grep -qF '_No lessons extracted from this session._' "$f" 2>/dev/null && continue
            echo "$mtime $f"
        done |
        sort -n | awk '{print $2}'
)

if [[ ${#LESSONS_FILES[@]} -eq 0 ]]; then
    log "No new lessons files since $CUTOFF_LABEL - nothing to prepare."
    emit_result 0
    exit 0
fi

log "Found ${#LESSONS_FILES[@]} new lessons file(s) since $CUTOFF_LABEL."

# ---------------------------------------------------------------------------
# Build the harvest input file
# ---------------------------------------------------------------------------
{
    echo "# Lessons Harvest Input - $DATE"
    echo ""

    for f in "${LESSONS_FILES[@]}"; do
        rel="${f#"$LESSONS_BASE/"}"
        mtime=$(stat -c "%Y" "$f" 2>/dev/null || echo 0)
        file_date=$(date -d "@$mtime" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

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

# The consumer writes this to the cursor file after a successful harvest.
NEWEST_FILE="${LESSONS_FILES[$(( ${#LESSONS_FILES[@]} - 1 ))]}"
CURSOR_EPOCH=$(stat -c "%Y" "$NEWEST_FILE" 2>/dev/null || echo 0)

write_manifest "$CURSOR_EPOCH" "${#LESSONS_FILES[@]}"

log "Collected ${#LESSONS_FILES[@]} file(s) -> $INPUT_FILE"
emit_result "${#LESSONS_FILES[@]}"
