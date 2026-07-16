#!/usr/bin/env bash
# weekly-lessons-trigger.sh
#
# Cron entry point for the weekly lessons harvest, run every Sunday at 02:00.
#
# Thin consumer of weekly-lessons-prepare.sh (the shared scan/collect logic,
# also used by the interactive skill):
#   1. Runs the prepare script, which collects the per-session lessons written
#      by daily-lessons since the last harvest into input.md plus manifest.json
#      under .claude/scheduled-session-digests/weekly-lessons/.
#   2. Substitutes the input/master paths into the prompt template
#      (weekly-lessons.md) and runs `claude --print`. The prompt instructs
#      Claude to distil project-generic lessons into the master file.
#   3. Advances the cursor file only after Claude exits successfully, so a
#      crash retries the same files on the next run.
#   4. Removes the staging dir and runs git-sync once.
#
# Dependencies: bash 4+, jq, git, claude CLI
#
# Cron setup (done by install.sh, or manually):
#   0 2 * * 0 /path/to/weekly-lessons-trigger.sh

set -euo pipefail

FULL_SCAN=false
for arg in "$@"; do
    case "$arg" in
        --full-scan) FULL_SCAN=true ;;
    esac
done

TAG="[weekly-lessons]"
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
LOG_FILE="$LOG_DIR/$(date '+%Y%m%d_%H%M%S')_weekly-lessons-trigger.log"

# ---------------------------------------------------------------------------
# Guards: everything this trigger needs is installed alongside it
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE="$SCRIPT_DIR/weekly-lessons-prepare.sh"
PROMPT_FILE="$SCRIPT_DIR/weekly-lessons.md"
GIT_SYNC="$SCRIPT_DIR/git-sync.sh"
STAGING_DIR="$META_DIR/.claude/scheduled-session-digests/weekly-lessons"
MANIFEST="$STAGING_DIR/manifest.json"

for required in "$PREPARE" "$PROMPT_FILE" "$GIT_SYNC"; do
    if [[ ! -f "$required" ]]; then
        log "Required file not found: $required - run install.sh first."
        exit 1
    fi
done

# Never leave staged files behind, even on a crash (they are gitignored, but
# the next prepare run should start from a clean dir).
cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Stage the work
# ---------------------------------------------------------------------------
PREPARE_ARGS=()
[[ "$FULL_SCAN" == true ]] && PREPARE_ARGS+=(--full-scan)
bash "$PREPARE" "${PREPARE_ARGS[@]+"${PREPARE_ARGS[@]}"}"

FILES=$(jq -r '.files' "$MANIFEST")
INPUT_FILE=$(jq -r '.input' "$MANIFEST")
MASTER_FILE=$(jq -r '.master' "$MANIFEST")
CURSOR_FILE=$(jq -r '.cursor' "$MANIFEST")
CURSOR_EPOCH=$(jq -r '.cursorEpoch' "$MANIFEST")

if [[ "$FILES" -eq 0 ]]; then
    log "Nothing to harvest."
    exit 0
fi

# ---------------------------------------------------------------------------
# Run Claude for analysis and master-file update
# ---------------------------------------------------------------------------
# The dedup/generalisation judgement is the hardest step and pollutes the
# permanent master file if done poorly, hence opus at high effort.
PROMPT=$(cat "$PROMPT_FILE")
PROMPT="${PROMPT//'{{INPUT_FILE}}'/$INPUT_FILE}"
PROMPT="${PROMPT//'{{MASTER_FILE}}'/$MASTER_FILE}"

cd "$META_DIR"
claude --model opus --effort high --print "$PROMPT"

# Only reached when Claude exits successfully (set -e), so a crash skips the
# cursor write and the same files are retried next run.
echo "$CURSOR_EPOCH" > "$CURSOR_FILE"
log "Cursor advanced to epoch $CURSOR_EPOCH."

bash "$GIT_SYNC" "weekly-lessons"

log "Done. Check $MASTER_FILE for updates."
