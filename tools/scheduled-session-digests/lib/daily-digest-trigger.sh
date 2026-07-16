#!/usr/bin/env bash
# daily-digest-trigger.sh
#
# Cron entry point for one daily digest scheduler (daily-summary at 02:00,
# daily-lessons at 03:00 - staggered to avoid concurrent git-sync commits on
# the same meta repo).
#
# Thin consumer of daily-digest-prepare.sh (the shared scan/stage logic, also
# used by the interactive skill):
#   1. Runs the prepare script, which stages one input file per new chat plus
#      manifest.json under .claude/scheduled-session-digests/<scheduler>/.
#   2. For each staged job, substitutes the job's input/output paths into the
#      scheduler's prompt template (<scheduler>.md) and runs `claude --print`.
#      The prompt instructs Claude to write the digest (or a no-content stub)
#      directly to the output path.
#   3. Advances the cursor file after each verified output, oldest-first, so a
#      crash or failed job retries exactly the unprocessed chats next run.
#   4. Removes the staging dir and runs git-sync once.
#
# Dependencies: bash 4+, jq, git, claude CLI
#
# Cron setup (done by install.sh, or manually):
#   0 2 * * * /path/to/daily-digest-trigger.sh daily-summary

set -euo pipefail

SCHEDULER="${1:-}"
case "$SCHEDULER" in
    # Per-scheduler model choice: summaries are cheap and high-frequency;
    # lessons extraction benefits from deeper reasoning.
    daily-summary) MODEL="haiku";  EFFORT="low" ;;
    daily-lessons) MODEL="sonnet"; EFFORT="medium" ;;
    *) echo "Usage: $(basename "$0") <daily-summary|daily-lessons> [--full-scan]"; exit 1 ;;
esac
shift

FULL_SCAN=false
for arg in "$@"; do
    case "$arg" in
        --full-scan) FULL_SCAN=true ;;
    esac
done

TAG="[$SCHEDULER]"
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
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_${SCHEDULER}-trigger.log"

# ---------------------------------------------------------------------------
# Guards: everything this trigger needs is installed alongside it
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE="$SCRIPT_DIR/daily-digest-prepare.sh"
PROMPT_FILE="$SCRIPT_DIR/$SCHEDULER.md"
GIT_SYNC="$SCRIPT_DIR/git-sync.sh"
STAGING_DIR="$META_DIR/.claude/scheduled-session-digests/$SCHEDULER"
MANIFEST="$STAGING_DIR/manifest.json"

for required in "$PREPARE" "$PROMPT_FILE" "$GIT_SYNC"; do
    if [[ ! -f "$required" ]]; then
        log "Required file not found: $required - run install.sh first."
        exit 1
    fi
done

# Never leave staged inputs behind, even on a crash (they are gitignored, but
# the next prepare run should start from a clean dir).
cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Stage the work
# ---------------------------------------------------------------------------
PREPARE_ARGS=()
[[ "$FULL_SCAN" == true ]] && PREPARE_ARGS+=(--full-scan)
bash "$PREPARE" "$SCHEDULER" "${PREPARE_ARGS[@]+"${PREPARE_ARGS[@]}"}"

JOB_COUNT=$(jq '.jobs | length' "$MANIFEST")
CURSOR_FILE=$(jq -r '.cursor' "$MANIFEST")
CURSOR_EPOCH=$(jq -r '.cursorEpoch' "$MANIFEST")

if [[ "$JOB_COUNT" -eq 0 ]]; then
    # No jobs staged. Recent chats may still have been deliberately skipped
    # (already processed / too short); advancing the cursor past them saves
    # rescanning them every run.
    [[ "$CURSOR_EPOCH" -gt 0 ]] && echo "$CURSOR_EPOCH" > "$CURSOR_FILE"
    log "Nothing to process."
    exit 0
fi

# ---------------------------------------------------------------------------
# Process each staged job with claude --print
# ---------------------------------------------------------------------------
TEMPLATE=$(cat "$PROMPT_FILE")
PROCESSED=0
ALL_OK=true

cd "$META_DIR"

while IFS=$'\t' read -r uuid date mtime input output; do
    log "Processing: $uuid ($date)..."

    prompt="${TEMPLATE//'{{INPUT_FILE}}'/$input}"
    prompt="${prompt//'{{OUTPUT_FILE}}'/$output}"
    # </dev/null so claude cannot consume the manifest stream feeding this loop
    claude --model "$MODEL" --effort "$EFFORT" --print "$prompt" < /dev/null || true

    if [[ -s "$output" ]]; then
        PROCESSED=$((PROCESSED + 1))
        log "Written: $output"
        # Jobs are oldest-first: advance the cursor over this chat only while
        # every earlier job succeeded, so a failed chat is retried next run.
        [[ "$ALL_OK" == true ]] && echo "$mtime" > "$CURSOR_FILE"
    else
        ALL_OK=false
        log "WARNING: no output produced for $uuid - it will be retried next run."
    fi

    rm -f "$input"
done < <(jq -r '.jobs[] | [.uuid, .date, (.mtime | tostring), .input, .output] | @tsv' "$MANIFEST")

# A fully successful run also advances past chats the prepare step skipped.
[[ "$ALL_OK" == true ]] && echo "$CURSOR_EPOCH" > "$CURSOR_FILE"

# ---------------------------------------------------------------------------
# Commit everything in one pass
# ---------------------------------------------------------------------------
if [[ $PROCESSED -gt 0 ]]; then
    bash "$GIT_SYNC" "$SCHEDULER"
    log "Done. Processed $PROCESSED chat(s)."
else
    log "No output produced - nothing to commit."
fi
