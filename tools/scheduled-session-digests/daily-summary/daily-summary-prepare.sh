#!/usr/bin/env bash
# daily-summary-prepare.sh
#
# Interactive-session variant of daily-summary-trigger.sh. Does everything the
# trigger does EXCEPT calling `claude --print` and git-sync. Instead of invoking
# Claude in a loop, it stages one input file per chat plus a manifest.json, and
# the /daily-summary skill (running inside an interactive Claude Code session)
# fans the summarisation out to subagents and commits afterwards.
#
# Stages:
#   $C4_CLAUDE_META_DIR/.claude/scheduler-jobs/daily-summary/<uuid>.md   (input)
#   $C4_CLAUDE_META_DIR/.claude/scheduler-jobs/daily-summary/manifest.json
# Each manifest entry records the input path and the final output path the
# subagent must write to: daily-summaries/YYYY/MM/<date>_<uuid>[_<title>].md
#
# Dependencies: bash 4+, jq, git
#
# Usage (normally invoked by the /daily-summary skill):
#   C4_CLAUDE_META_DIR=/path/to/claude-meta ./daily-summary-prepare.sh [--full-scan]

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

# Source env file if C4_CLAUDE_META_DIR is not already set
ENV_FILE="$HOME/.claude/claude-scheduler.env"
if [[ -z "${C4_CLAUDE_META_DIR:-}" ]] && [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

META_DIR="${C4_CLAUDE_META_DIR:-}"
if [[ -z "$META_DIR" ]]; then
    log "[daily-summary-prepare] C4_CLAUDE_META_DIR is not set - aborting."
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
JOBS_DIR="$META_DIR/.claude/scheduler-jobs/daily-summary"
MANIFEST="$JOBS_DIR/manifest.json"

# Keep the transient staging area out of git so a partial run is never committed.
GITIGNORE="$META_DIR/.gitignore"
if ! grep -q "^.claude/scheduler-jobs/" "$GITIGNORE" 2>/dev/null; then
    echo ".claude/scheduler-jobs/" >> "$GITIGNORE"
fi

# Build list of existing project dirs to scan
SCAN_DIRS=()
[[ -d "$PROJECTS_DIR" ]] && SCAN_DIRS+=("$PROJECTS_DIR")
[[ -d "$DEVCONTAINER_PROJECTS_DIR" ]] && SCAN_DIRS+=("$DEVCONTAINER_PROJECTS_DIR")

# Reset staging dir and write an empty manifest up front.
rm -rf "$JOBS_DIR"
mkdir -p "$JOBS_DIR"
echo "[]" > "$MANIFEST"

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
    log "[daily-summary-prepare] No projects directory found (checked $PROJECTS_DIR and $DEVCONTAINER_PROJECTS_DIR) - nothing to prepare."
    echo "MANIFEST=$MANIFEST"
    echo "JOBS=0"
    exit 0
fi

# ---------------------------------------------------------------------------
# Determine cutoff: modification time of the most recently written summary
# ---------------------------------------------------------------------------
LAST_SUMMARY=$(find "$SUMMARIES_BASE" -name "*.md" -type f 2>/dev/null \
    | while IFS= read -r f; do echo "$(stat --format="%Y" "$f" 2>/dev/null || echo 0) $f"; done \
    | sort -rn | head -1 | awk '{print $2}' || true)

if [[ "$FULL_SCAN" == true ]]; then
    log "[daily-summary-prepare] Full scan requested - scanning again from the first chat history."
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
    log "[daily-summary-prepare] No chat histories updated since $CUTOFF_LABEL - nothing to prepare."
    echo "MANIFEST=$MANIFEST"
    echo "JOBS=0"
    exit 0
fi

log "[daily-summary-prepare] Found ${#RECENT_FILES[@]} chat(s) modified since $CUTOFF_LABEL."

JOBS_TMP=$(mktemp)
TRANSCRIPT_TMP=""
cleanup() {
    [[ -n "${TRANSCRIPT_TMP:-}" ]] && rm -f "$TRANSCRIPT_TMP"
    rm -f "$JOBS_TMP"
}
trap cleanup EXIT INT TERM

PREPARED=0

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

    if find "$SUMMARIES_BASE" -name "*${UUID}*" -type f 2>/dev/null | grep -q .; then
        log "[daily-summary-prepare] Already summarised: $UUID - skipping."
        continue
    fi

    log "[daily-summary-prepare] Staging: $UUID ($CHAT_DATE)..."

    # ---- Extract metadata and transcript from JSONL ----
    TITLE=""
    CWD_VAL=""
    USER_TURNS=0
    TRANSCRIPT_TMP=$(mktemp)

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

    if [[ $TRANSCRIPT_LEN -eq 0 ]]; then
        log "[daily-summary-prepare] No new messages in $UUID after cutoff - skipping."
        rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""
        continue
    fi

    if [[ $USER_TURNS -lt $MIN_USER_TURNS ]] || [[ $TRANSCRIPT_LEN -lt $MIN_TRANSCRIPT_CHARS ]]; then
        log "[daily-summary-prepare] Skipping $UUID - too short ($USER_TURNS turn(s), $TRANSCRIPT_LEN chars)."
        rm -f "$TRANSCRIPT_TMP"; TRANSCRIPT_TMP=""
        continue
    fi

    PROJECT_NAME=$(basename "${CWD_VAL:-unknown}")
    [[ -z "$TITLE" ]] && TITLE="$UUID"

    if [[ "$TITLE" != "$UUID" ]]; then
        SAFE_TITLE=$(echo "$TITLE" | tr '\\/:*?"<>|' '-' | tr ' ' '_')
        OUT_NAME="${CHAT_DATE}_${UUID}_${SAFE_TITLE}.md"
    else
        OUT_NAME="${CHAT_DATE}_${UUID}.md"
    fi
    OUT_FILE="$SUMMARIES_DIR/$OUT_NAME"
    INPUT_FILE="$JOBS_DIR/$UUID.md"

    # ---- Write per-chat input file for the subagent ----
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

    # ---- Record the job ----
    jq -nc \
        --arg uuid "$UUID" \
        --arg date "$CHAT_DATE" \
        --arg title "$TITLE" \
        --arg project "$PROJECT_NAME" \
        --arg input "$INPUT_FILE" \
        --arg output "$OUT_FILE" \
        '{uuid:$uuid, date:$date, title:$title, project:$project, input:$input, output:$output}' \
        >> "$JOBS_TMP"

    PREPARED=$((PREPARED + 1))
done

jq -s '.' "$JOBS_TMP" > "$MANIFEST"

log "[daily-summary-prepare] Staged $PREPARED job(s) -> $MANIFEST"
echo "MANIFEST=$MANIFEST"
echo "JOBS=$PREPARED"
