#!/usr/bin/env bash
# daily-lessons-trigger.sh
#
# Triggered by cron at 03:00 daily (staggered from daily-summary at 02:00 to
# avoid concurrent git-sync conflicts on the same meta repo).
# Scans ~/.claude/projects/**/*.jsonl for files modified since the last run,
# extracts each conversation transcript, and passes it to Claude for lessons
# extraction via the ceh-lessons-learned skill.
# Each chat gets its own file: lessons-learned/YYYY/MM/<date>_<uuid>[_<title>].md
# Short transcripts are skipped based on thresholds in scheduler-config.json (default: < 2 turns or < 500 chars).
# Sessions that produce no lessons get a stub file so they are not reprocessed.
# After all chats are processed a single git-sync commit is made.
#
# Dependencies: bash 4+, jq, git, claude CLI
#
# Cron setup (done by install.sh, or manually):
#   0 3 * * * C4_CLAUDE_META_DIR=/path/to/claude-meta /path/to/daily-lessons-trigger.sh

set -euo pipefail

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$line"
    [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >> "$LOG_FILE"
}

FULL_SCAN=false

for arg in "$@"; do
    case "$arg" in
        --full-scan)
            FULL_SCAN=true
            ;;
    esac
done

# Source env file if C4_CLAUDE_META_DIR is not already set (needed for cron)
ENV_FILE="$HOME/.claude/claude-scheduler.env"
if [[ -z "${C4_CLAUDE_META_DIR:-}" ]] && [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

META_DIR="${C4_CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    log "[daily-lessons] C4_CLAUDE_META_DIR is not set - aborting."
    exit 1
fi

LOG_DIR="$META_DIR/logs"
mkdir -p "$LOG_DIR"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCRIPT_NAME}.log"

META_DIR_NAME="$(basename "$META_DIR")"

# ---------------------------------------------------------------------------
# Read configurable thresholds from scheduler-config.json (written by install.sh)
# ---------------------------------------------------------------------------
MIN_USER_TURNS=2
MIN_TRANSCRIPT_CHARS=500
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/scheduler-config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    val=$(jq -r '.dailyLessons.minUserTurns // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_USER_TURNS="$val"
    val=$(jq -r '.dailyLessons.minTranscriptChars // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_TRANSCRIPT_CHARS="$val"
fi

PROJECTS_DIR="$HOME/.claude/projects"
DEVCONTAINER_PROJECTS_DIR="$HOME/.claude_devcontainer/projects"
LESSONS_BASE="$META_DIR/lessons-learned"
LESSONS_STAGING="$META_DIR/docs/claude_logs/LESSONS_LEARNED.md"
PROMPT_FILE="$SCRIPT_DIR/daily-lessons.md"
INPUT_FILE="$SCRIPT_DIR/lessons-input.md"
GIT_SYNC="$SCRIPT_DIR/git-sync.sh"

if [[ ! -f "$PROMPT_FILE" ]]; then
    log "[daily-lessons] Prompt file not found at $PROMPT_FILE - run install.sh first."
    exit 1
fi
if [[ ! -f "$GIT_SYNC" ]]; then
    log "[daily-lessons] git-sync.sh not found at $GIT_SYNC - run install.sh first."
    exit 1
fi

# Build list of existing project dirs to scan
SCAN_DIRS=()
[[ -d "$PROJECTS_DIR" ]] && SCAN_DIRS+=("$PROJECTS_DIR")
[[ -d "$DEVCONTAINER_PROJECTS_DIR" ]] && SCAN_DIRS+=("$DEVCONTAINER_PROJECTS_DIR")

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
    log "[daily-lessons] No projects directory found (checked $PROJECTS_DIR and $DEVCONTAINER_PROJECTS_DIR) - skipping."
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine cutoff: modification time of the most recently written lessons file
# ---------------------------------------------------------------------------
LAST_FILE=$(find "$LESSONS_BASE" -name "*.md" -type f 2>/dev/null \
    | while IFS= read -r f; do echo "$(stat --format="%Y" "$f" 2>/dev/null || echo 0) $f"; done \
    | sort -rn | head -1 | awk '{print $2}' || true)

if [[ "$FULL_SCAN" == true ]]; then
    log "[daily-lessons] Full scan requested - scanning again from the first chat history."
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (full scan)"
elif [[ -n "$LAST_FILE" ]]; then
    CUTOFF_EPOCH=$(stat --format="%Y" "$LAST_FILE")
    CUTOFF_LABEL=$(date -d "@$CUTOFF_EPOCH" +"%Y-%m-%d %H:%M")
else
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (first run)"
fi

# ---------------------------------------------------------------------------
# Find JSONL files modified after the cutoff, sorted oldest-first
# ---------------------------------------------------------------------------
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
    log "[daily-lessons] No chat histories updated since $CUTOFF_LABEL - skipping."
    exit 0
fi

log "[daily-lessons] Found ${#RECENT_FILES[@]} chat(s) modified since $CUTOFF_LABEL."
mkdir -p "$LESSONS_BASE"

PROMPT=$(cat "$PROMPT_FILE")
PROCESSED=0

# Cleanup on exit: remove transient files and the staging file so it never
# gets accidentally committed by git-sync if the trigger crashes mid-run.
TRANSCRIPT_TMP=""
cleanup() {
    [[ -n "${TRANSCRIPT_TMP:-}" ]] && rm -f "$TRANSCRIPT_TMP"
    rm -f "$INPUT_FILE"
    rm -f "$LESSONS_STAGING"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Process each chat file
# ---------------------------------------------------------------------------
for file in "${RECENT_FILES[@]}"; do
    UUID=$(basename "$file" .jsonl)
    FILE_MTIME=$(stat --format="%Y" "$file" 2>/dev/null) || continue
    CHAT_DATE=$(date -d "@$FILE_MTIME" +"%Y-%m-%d")
    YEAR=$(date -d "@$FILE_MTIME" +"%Y")
    MONTH=$(date -d "@$FILE_MTIME" +"%m")
    LESSONS_DIR="$LESSONS_BASE/$YEAR/$MONTH"

    # Skip check: search entire base tree regardless of year/month subfolder
    if find "$LESSONS_BASE" -name "*${UUID}*" -type f 2>/dev/null | grep -q .; then
        log "[daily-lessons] Already processed: $UUID - skipping."
        continue
    fi

    log "[daily-lessons] Processing: $UUID ($CHAT_DATE)..."

    # ---- Extract metadata and transcript from JSONL ----
    TITLE=""
    CWD_VAL=""
    USER_TURNS=0
    TRANSCRIPT_TMP=$(mktemp)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

        # Always capture metadata regardless of timestamp
        if [[ "$type" == "custom-title" ]] && [[ -z "$TITLE" ]]; then
            TITLE=$(echo "$line" | jq -r '.customTitle // empty' 2>/dev/null || true)
        fi
        if [[ -z "$CWD_VAL" ]]; then
            new_cwd=$(echo "$line" | jq -r '.cwd // empty' 2>/dev/null || true)
            [[ -n "$new_cwd" ]] && CWD_VAL="$new_cwd"
        fi

        # Skip entries at or before the cutoff
        if [[ $CUTOFF_EPOCH -gt 0 ]]; then
            ts=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null || true)
            if [[ -n "$ts" ]]; then
                ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
                [[ $ts_epoch -le $CUTOFF_EPOCH ]] && continue
            fi
        fi

        if [[ "$type" == "user" ]]; then
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
                if [[ ${#text} -gt 2000 ]]; then
                    text="${text:0:2000}"$'\n[...truncated]'
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

    # Skip if nothing to process
    if [[ $TRANSCRIPT_LEN -eq 0 ]]; then
        log "[daily-lessons] No new messages in $UUID after cutoff - skipping."
        rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""
        continue
    fi

    # Short-session filter (thresholds read from scheduler-config.json)
    if [[ $USER_TURNS -lt $MIN_USER_TURNS ]] || [[ $TRANSCRIPT_LEN -lt $MIN_TRANSCRIPT_CHARS ]]; then
        log "[daily-lessons] Skipping $UUID - too short ($USER_TURNS turn(s), $TRANSCRIPT_LEN chars)."
        rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""
        continue
    fi

    PROJECT_NAME=$(basename "${CWD_VAL:-unknown}")
    [[ -z "$TITLE" ]] && TITLE="$UUID"

    # Build output filename
    if [[ "$TITLE" != "$UUID" ]]; then
        SAFE_TITLE=$(echo "$TITLE" | tr '\\/:*?"<>|' '-' | tr ' ' '_')
        OUT_NAME="${CHAT_DATE}_${UUID}_${SAFE_TITLE}.md"
    else
        OUT_NAME="${CHAT_DATE}_${UUID}.md"
    fi

    mkdir -p "$LESSONS_DIR"
    OUT_FILE="$LESSONS_DIR/$OUT_NAME"

    # ---- Write input file for Claude ----
    cat > "$INPUT_FILE" <<EOF
# Lessons Input
UUID: $UUID
Date: $CHAT_DATE
Title: $TITLE
Project: $PROJECT_NAME
CWD: $CWD_VAL

## Conversation

EOF
    cat "$TRANSCRIPT_TMP" >> "$INPUT_FILE"
    rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""

    # ---- Clear staging file so the skill writes a fresh one ----
    mkdir -p "$(dirname "$LESSONS_STAGING")"
    rm -f "$LESSONS_STAGING"

    # ---- Invoke Claude ----
    cd "$META_DIR"
    claude --print "$PROMPT"

    # ---- Move or stub the output ----
    if [[ -f "$LESSONS_STAGING" ]] && [[ -s "$LESSONS_STAGING" ]]; then
        mv "$LESSONS_STAGING" "$OUT_FILE"
        log "[daily-lessons] Written: $OUT_FILE"
    else
        # Write a stub so the UUID is marked as processed and not retried.
        rm -f "$LESSONS_STAGING"
        cat > "$OUT_FILE" <<EOF
# Lessons - $CHAT_DATE
**Session**: $UUID
**Title**: $TITLE
**Project**: $PROJECT_NAME

_No lessons extracted from this session._
EOF
        log "[daily-lessons] No lessons produced for $UUID - stub written."
    fi

    rm -f "$INPUT_FILE"
    PROCESSED=$((PROCESSED + 1))
done

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if [[ $PROCESSED -gt 0 ]]; then
    bash "$GIT_SYNC" "daily-lessons"
    log "[daily-lessons] Done. Processed $PROCESSED chat(s)."
else
    log "[daily-lessons] All recent chats already processed - nothing to commit."
fi
