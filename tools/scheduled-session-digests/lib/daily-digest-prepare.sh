#!/usr/bin/env bash
# daily-digest-prepare.sh
#
# Stages new Claude Code chats for one daily digest scheduler. Shared by both
# schedulers and both run mechanisms:
#   - cron : daily-digest-trigger.sh runs this, then feeds each staged job to
#            `claude --print`.
#   - skill: the /session-digest-<scheduler> skill runs this, then fans the
#            staged jobs out to subagents.
#
# What it does:
#   1. Reads the cursor file ($C4_CLAUDE_META_DIR/.claude/<scheduler>-cursor,
#      Unix epoch mtime of the newest chat handled on the last successful run)
#      to determine the scan cutoff.
#   2. Scans ~/.claude/projects/**/*.jsonl (and ~/.claude_devcontainer) for chat
#      files with mtime > cutoff, skipping already-processed UUIDs and sessions
#      below the configured turn/length thresholds.
#   3. Writes one input file per staged chat plus manifest.json to the staging
#      dir $C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/<scheduler>/
#      (gitignored, reset on every run).
#
# The consumer advances the cursor only over jobs whose output file exists, so
# a crash retries the unprocessed chats on the next run (see the trigger and
# SKILL.md for the exact rule).
#
# Manifest shape:
#   { "scheduler":   "<name>",
#     "cursor":      "<cursor file path>",
#     "cursorEpoch": <epoch to write to the cursor after a fully successful run>,
#     "jobs": [ { "uuid", "date", "title", "project", "mtime",
#                 "input": "<staged input path>", "output": "<final output path>" } ] }
#
# Dependencies: bash 4+, jq
#
# Usage:
#   daily-digest-prepare.sh <daily-summary|daily-lessons> [--full-scan]

set -euo pipefail

SCHEDULER="${1:-}"
case "$SCHEDULER" in
    daily-summary) OUTPUT_SUBDIR="daily-summaries"; CONFIG_KEY="dailySummary" ;;
    daily-lessons) OUTPUT_SUBDIR="lessons-learned"; CONFIG_KEY="dailyLessons" ;;
    *) echo "Usage: $(basename "$0") <daily-summary|daily-lessons> [--full-scan]"; exit 1 ;;
esac
shift

FULL_SCAN=false
for arg in "$@"; do
    case "$arg" in
        --full-scan) FULL_SCAN=true ;;
    esac
done

TAG="[$SCHEDULER-prepare]"
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
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCHEDULER}-prepare.log"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
META_DIR_NAME="$(basename "$META_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="$HOME/.claude/projects"
DEVCONTAINER_PROJECTS_DIR="$HOME/.claude_devcontainer/projects"
OUTPUT_BASE="$META_DIR/$OUTPUT_SUBDIR"
STAGING_DIR="$META_DIR/.claude/scheduled-session-digests/$SCHEDULER"
MANIFEST="$STAGING_DIR/manifest.json"
CURSOR_FILE="$META_DIR/.claude/${SCHEDULER}-cursor"

# Keep the transient staging area out of git so a partial run is never committed.
GITIGNORE="$META_DIR/.gitignore"
if ! grep -qF ".claude/scheduled-session-digests/" "$GITIGNORE" 2>/dev/null; then
    echo ".claude/scheduled-session-digests/" >> "$GITIGNORE"
fi

# ---------------------------------------------------------------------------
# Thresholds from scheduler-config.json (written by install.sh)
# ---------------------------------------------------------------------------
MIN_USER_TURNS=2
MIN_TRANSCRIPT_CHARS=500
CONFIG_FILE="$SCRIPT_DIR/scheduler-config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    val=$(jq -r ".${CONFIG_KEY}.minUserTurns // empty" "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_USER_TURNS="$val"
    val=$(jq -r ".${CONFIG_KEY}.minTranscriptChars // empty" "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_TRANSCRIPT_CHARS="$val"
fi

# ---------------------------------------------------------------------------
# Reset the staging dir and write an empty manifest up front so the consumer
# always has something valid to read.
# ---------------------------------------------------------------------------
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

write_manifest() {
    # $1 = file with one job object per line (may be empty), $2 = cursor epoch
    jq -s \
        --arg scheduler "$SCHEDULER" \
        --arg cursor "$CURSOR_FILE" \
        --argjson cursorEpoch "$2" \
        '{scheduler: $scheduler, cursor: $cursor, cursorEpoch: $cursorEpoch, jobs: .}' \
        "$1" > "$MANIFEST"
}

emit_result() {
    echo "MANIFEST=$MANIFEST"
    echo "JOBS=$1"
}

JOBS_TMP="$STAGING_DIR/jobs.tmp"
TRANSCRIPT_TMP="$STAGING_DIR/transcript.tmp"
: > "$JOBS_TMP"
write_manifest "$JOBS_TMP" 0

# Working temps live inside the staging dir; remove them on any exit so only
# the staged inputs and the manifest remain.
cleanup() { rm -f "$JOBS_TMP" "$TRANSCRIPT_TMP"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Determine the scan cutoff from the cursor file
# ---------------------------------------------------------------------------
if [[ "$FULL_SCAN" == true ]]; then
    log "Full scan requested - scanning again from the first chat history."
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
# Find chat JSONL files modified after the cutoff, sorted oldest-first.
# The meta repo's own chats are excluded.
# ---------------------------------------------------------------------------
SCAN_DIRS=()
[[ -d "$PROJECTS_DIR" ]] && SCAN_DIRS+=("$PROJECTS_DIR")
[[ -d "$DEVCONTAINER_PROJECTS_DIR" ]] && SCAN_DIRS+=("$DEVCONTAINER_PROJECTS_DIR")

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
    log "No projects directory found (checked $PROJECTS_DIR and $DEVCONTAINER_PROJECTS_DIR) - nothing to prepare."
    emit_result 0
    exit 0
fi

readarray -t RECENT_FILES < <(
    for root in "${SCAN_DIRS[@]}"; do
        find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
            while IFS= read -r project_dir; do
                [[ "$(basename "$project_dir")" == *"$META_DIR_NAME"* ]] && continue
                find "$project_dir" -name "*.jsonl" -type f 2>/dev/null |
                    while IFS= read -r f; do
                        mtime=$(stat -c "%Y" "$f" 2>/dev/null || echo 0)
                        [[ $mtime -gt $CUTOFF_EPOCH ]] && echo "$mtime $f"
                    done
            done
    done | sort -n | awk '{print $2}'
)

if [[ ${#RECENT_FILES[@]} -eq 0 ]]; then
    log "No chat histories updated since $CUTOFF_LABEL - nothing to prepare."
    emit_result 0
    exit 0
fi

log "Found ${#RECENT_FILES[@]} chat(s) modified since $CUTOFF_LABEL."

# Every recent file ends this run either staged or deliberately skipped, so a
# fully successful run may advance the cursor to the newest recent file's mtime.
NEWEST_FILE="${RECENT_FILES[$(( ${#RECENT_FILES[@]} - 1 ))]}"
CURSOR_EPOCH=$(stat -c "%Y" "$NEWEST_FILE" 2>/dev/null || echo 0)

# ---------------------------------------------------------------------------
# Stage one input file per chat
# ---------------------------------------------------------------------------
PREPARED=0

for file in "${RECENT_FILES[@]}"; do
    UUID=$(basename "$file" .jsonl)
    FILE_MTIME=$(stat -c "%Y" "$file" 2>/dev/null) || continue
    CHAT_DATE=$(date -d "@$FILE_MTIME" +"%Y-%m-%d")
    OUTPUT_DIR="$OUTPUT_BASE/$(date -d "@$FILE_MTIME" +"%Y/%m")"

    # Skip check: search the entire output tree so existing files are found
    # regardless of which year/month folder they landed in.
    if find "$OUTPUT_BASE" -name "*${UUID}*" -type f 2>/dev/null | grep -q .; then
        log "Already processed: $UUID - skipping."
        continue
    fi

    log "Staging: $UUID ($CHAT_DATE)..."

    # ---- Extract metadata and transcript from the JSONL ----
    # Metadata (title, cwd) is read from the whole file; conversation entries at
    # or before the cutoff are dropped so only the new portion of a long-running
    # session is digested.
    TITLE=""
    CWD_VAL=""
    USER_TURNS=0
    : > "$TRANSCRIPT_TMP"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

        if [[ "$type" == "custom-title" ]] && [[ -z "$TITLE" ]]; then
            TITLE=$(echo "$line" | jq -r '.customTitle // empty' 2>/dev/null || true)
        fi
        if [[ -z "$CWD_VAL" ]]; then
            new_cwd=$(echo "$line" | jq -r '.cwd // empty' 2>/dev/null || true)
            [[ -n "$new_cwd" ]] && CWD_VAL="$new_cwd"
        fi

        if [[ $CUTOFF_EPOCH -gt 0 ]]; then
            ts=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null || true)
            if [[ -n "$ts" ]]; then
                ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
                [[ $ts_epoch -le $CUTOFF_EPOCH ]] && continue
            fi
        fi

        if [[ "$type" == "user" ]]; then
            # content is a plain string or an array of content blocks
            content=$(echo "$line" | jq -r '
                .message.content |
                if type == "string" then .
                elif type == "array" then map(select(.type == "text") | .text) | join("\n")
                else tostring end
            ' 2>/dev/null || true)
            if [[ -n "$content" ]]; then
                USER_TURNS=$((USER_TURNS + 1))
                printf '[USER]\n%s\n\n' "$content" >> "$TRANSCRIPT_TMP"
            fi
        elif [[ "$type" == "assistant" ]]; then
            while IFS= read -r text; do
                [[ -z "$text" ]] && continue
                if [[ ${#text} -gt 10000 ]]; then
                    text="${text:0:10000}"$'\n[...truncated]'
                fi
                printf '[ASSISTANT]\n%s\n\n' "$text" >> "$TRANSCRIPT_TMP"
            done < <(echo "$line" | jq -r '
                .message.content // [] |
                if type == "array" then .[] | select(.type == "text") | .text
                else . end
            ' 2>/dev/null || true)
        fi
    done < "$file"

    TRANSCRIPT_LEN=$(wc -c < "$TRANSCRIPT_TMP" || echo 0)

    if [[ $TRANSCRIPT_LEN -eq 0 ]]; then
        log "No new messages in $UUID after cutoff - skipping."
        continue
    fi

    if [[ $USER_TURNS -lt $MIN_USER_TURNS ]] || [[ $TRANSCRIPT_LEN -lt $MIN_TRANSCRIPT_CHARS ]]; then
        log "Skipping $UUID - too short ($USER_TURNS turn(s), $TRANSCRIPT_LEN chars)."
        continue
    fi

    PROJECT_NAME=$(basename "${CWD_VAL:-unknown}")
    [[ -z "$TITLE" ]] && TITLE="$UUID"

    # Output filename: <date>_<uuid>_<safe-title>.md, title omitted if none set.
    if [[ "$TITLE" != "$UUID" ]]; then
        SAFE_TITLE=$(echo "$TITLE" | tr '\\/:*?"<>|' '_' | tr ' ' '_')
        OUT_NAME="${CHAT_DATE}_${UUID}_${SAFE_TITLE}.md"
    else
        OUT_NAME="${CHAT_DATE}_${UUID}.md"
    fi
    OUT_FILE="$OUTPUT_DIR/$OUT_NAME"
    INPUT_FILE="$STAGING_DIR/$UUID.md"

    cat > "$INPUT_FILE" <<EOF
# Session Transcript
UUID: $UUID
Date: $CHAT_DATE
Title: $TITLE
Project: $PROJECT_NAME
CWD: $CWD_VAL
Output: $OUT_FILE

## Conversation

EOF
    cat "$TRANSCRIPT_TMP" >> "$INPUT_FILE"

    jq -nc \
        --arg uuid "$UUID" \
        --arg date "$CHAT_DATE" \
        --arg title "$TITLE" \
        --arg project "$PROJECT_NAME" \
        --argjson mtime "$FILE_MTIME" \
        --arg input "$INPUT_FILE" \
        --arg output "$OUT_FILE" \
        '{uuid:$uuid, date:$date, title:$title, project:$project, mtime:$mtime, input:$input, output:$output}' \
        >> "$JOBS_TMP"

    PREPARED=$((PREPARED + 1))
done

write_manifest "$JOBS_TMP" "$CURSOR_EPOCH"

log "Staged $PREPARED job(s) -> $MANIFEST"
emit_result "$PREPARED"
