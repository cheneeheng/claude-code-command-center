#!/usr/bin/env bash
# daily-summary-trigger.sh
#
# Triggered by cron at 02:00 daily.
# Scans ~/.claude/projects/**/*.jsonl for files modified since the last run,
# extracts each conversation transcript, and passes it to Claude for summarisation.
# Each chat gets its own summary file: daily-summaries/YYYY/MM/<date>_<uuid>[_<title>].md
# Short transcripts are skipped based on thresholds in scheduler-config.json (default: < 2 turns or < 500 chars).
# After all chats are processed a single git-sync commit is made.
#
# Dependencies: bash 4+, jq, git, claude CLI
#
# Cron setup (done by install.sh, or manually):
#   0 2 * * * C4_CLAUDE_META_DIR=/path/to/claude-meta /path/to/daily-summary-trigger.sh

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
    log "[daily-summary] C4_CLAUDE_META_DIR is not set - aborting."
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
    val=$(jq -r '.dailySummary.minUserTurns // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_USER_TURNS="$val"
    val=$(jq -r '.dailySummary.minTranscriptChars // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$val" ]] && MIN_TRANSCRIPT_CHARS="$val"
fi

PROJECTS_DIR="$HOME/.claude/projects"
DEVCONTAINER_PROJECTS_DIR="$HOME/.claude_devcontainer/projects"
SUMMARIES_BASE="$META_DIR/daily-summaries"
PROMPT_FILE="$SCRIPT_DIR/daily-summary.md"
INPUT_FILE="$SCRIPT_DIR/chat-input.md"
GIT_SYNC="$SCRIPT_DIR/git-sync.sh"

if [[ ! -f "$PROMPT_FILE" ]]; then
    log "[daily-summary] Prompt file not found at $PROMPT_FILE - run install.sh first."
    exit 1
fi
if [[ ! -f "$GIT_SYNC" ]]; then
    log "[daily-summary] git-sync.sh not found at $GIT_SYNC - run install.sh first."
    exit 1
fi
# Build list of existing project dirs to scan
SCAN_DIRS=()
[[ -d "$PROJECTS_DIR" ]] && SCAN_DIRS+=("$PROJECTS_DIR")
[[ -d "$DEVCONTAINER_PROJECTS_DIR" ]] && SCAN_DIRS+=("$DEVCONTAINER_PROJECTS_DIR")

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
    log "[daily-summary] No projects directory found (checked $PROJECTS_DIR and $DEVCONTAINER_PROJECTS_DIR) - skipping."
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine cutoff: modification time of the most recently written summary
# ---------------------------------------------------------------------------
LAST_SUMMARY=$(find "$SUMMARIES_BASE" -name "*.md" -type f 2>/dev/null \
    | while IFS= read -r f; do echo "$(stat --format="%Y" "$f" 2>/dev/null || echo 0) $f"; done \
    | sort -rn | head -1 | awk '{print $2}' || true)

if [[ "$FULL_SCAN" == true ]]; then
    log "[daily-summary] Full scan requested - scanning again from the first chat history."
    CUTOFF_EPOCH=0
    CUTOFF_LABEL="beginning of time (full scan)"
elif [[ -n "$LAST_SUMMARY" ]]; then
    CUTOFF_EPOCH=$(stat --format="%Y" "$LAST_SUMMARY")
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
    log "[daily-summary] No chat histories updated since $CUTOFF_LABEL - skipping."
    exit 0
fi

log "[daily-summary] Found ${#RECENT_FILES[@]} chat(s) modified since $CUTOFF_LABEL."
mkdir -p "$SUMMARIES_BASE"

PROMPT=$(cat "$PROMPT_FILE")
PROCESSED=0

# Cleanup on exit
TRANSCRIPT_TMP=""
cleanup() {
    [[ -n "${TRANSCRIPT_TMP:-}" ]] && rm -f "$TRANSCRIPT_TMP"
    rm -f "$INPUT_FILE"
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
    SUMMARIES_DIR="$SUMMARIES_BASE/$YEAR/$MONTH"

    # Skip check: search entire base tree regardless of year/month subfolder
    if find "$SUMMARIES_BASE" -name "*${UUID}*" -type f 2>/dev/null | grep -q .; then
        log "[daily-summary] Already summarised: $UUID - skipping."
        continue
    fi

    log "[daily-summary] Processing: $UUID ($CHAT_DATE)..."

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

    # Skip if nothing to summarise
    if [[ $TRANSCRIPT_LEN -eq 0 ]]; then
        log "[daily-summary] No new messages in $UUID after cutoff - skipping."
        rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""
        continue
    fi

    # Short-session filter (thresholds read from scheduler-config.json)
    if [[ $USER_TURNS -lt $MIN_USER_TURNS ]] || [[ $TRANSCRIPT_LEN -lt $MIN_TRANSCRIPT_CHARS ]]; then
        log "[daily-summary] Skipping $UUID - too short ($USER_TURNS turn(s), $TRANSCRIPT_LEN chars)."
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

    mkdir -p "$SUMMARIES_DIR"
    OUT_FILE="$SUMMARIES_DIR/$OUT_NAME"

    # ---- Write input file for Claude ----
    cat > "$INPUT_FILE" <<EOF
# Chat History Input
UUID: $UUID
Date: $CHAT_DATE
Title: $TITLE
Project: $PROJECT_NAME
CWD: $CWD_VAL
Output: $OUT_FILE

## Conversation

EOF
    cat "$TRANSCRIPT_TMP" >> "$INPUT_FILE"
    rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""

    # ---- Invoke Claude ----
    cd "$META_DIR"
    claude --model haiku --effort low --print "$PROMPT"

    rm -f "$INPUT_FILE"
    PROCESSED=$((PROCESSED + 1))
done

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if [[ $PROCESSED -gt 0 ]]; then
    bash "$GIT_SYNC" "daily-summary"
    log "[daily-summary] Done. Summarised $PROCESSED chat(s)."
else
    log "[daily-summary] All recent chats already summarised - nothing to commit."
fi
