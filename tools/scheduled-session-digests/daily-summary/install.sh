#!/usr/bin/env bash
# install.sh - daily-summary scheduler
#
# Run once from this directory.
#
# What it does:
#   1. Checks dependencies (jq, git, claude)
#   2. Initialises $C4_CLAUDE_META_DIR (git repo) with required subdirs
#   3. Sets C4_CLAUDE_META_DIR in ~/.claude/claude-scheduler.env (sourced by triggers)
#   4. Copies daily-summary.md, daily-summary-trigger.sh, git-sync.sh to scripts dir
#   5. Registers a cron job (02:00 daily)
#
# How it works:
#   At 02:00 the trigger scans ~/.claude/projects/**/*.jsonl for new chat files,
#   passes each transcript to Claude for summarisation, and commits the results.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="${C4_CLAUDE_META_DIR:-$HOME/claude-meta}"
SCRIPTS_DIR="$META_DIR/.claude/scripts"
ENV_FILE="$HOME/.claude/claude-scheduler.env"

# Mode selects which mechanism to install:
#   skill - prepare script + interactive SKILL.md (no cron, no claude -p)
#   cron  - trigger script + cron job (claude -p based)
#   both  - everything (default)
MODE="${1:-both}"
case "$MODE" in
    skill|cron|both) ;;
    *) echo "  ERROR: unknown mode '$MODE' (expected skill|cron|both)"; exit 1 ;;
esac
WANT_CRON=false; WANT_SKILL=false
[[ "$MODE" == cron  || "$MODE" == both ]] && WANT_CRON=true
[[ "$MODE" == skill || "$MODE" == both ]] && WANT_SKILL=true

STEP=0
step() { STEP=$((STEP + 1)); echo "[$STEP] $*"; }

prompt_input() {
    local label="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" [$default]"
    read -r -p "  ${label}${hint}: " value || true
    if [[ -z "$value" ]] && [[ -n "$default" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

echo ""
echo "=== Daily Summary Scheduler - Install ==="
echo "Meta repo   : $META_DIR"
echo "Scripts dir : $SCRIPTS_DIR"
echo "Mode        : $MODE"
echo ""

# ---- Schedule settings -------------------------------------------------------
echo "  Schedule settings (press Enter to keep defaults):"
SCHEDULE_TIME="02:00"
$WANT_CRON && SCHEDULE_TIME=$(prompt_input "  Run time (HH:MM, 24h)" "02:00")
MIN_USER_TURNS=$(prompt_input "  Min user turns to process a session" "2")
MIN_TRANSCRIPT_CHARS=$(prompt_input "  Min transcript length (chars) to process a session" "500")
echo ""

CRON_HOUR=$(echo "$SCHEDULE_TIME" | cut -d: -f1)
CRON_MIN=$(echo "$SCHEDULE_TIME" | cut -d: -f2)

# ---------------------------------------------------------------------------
# 1. Check dependencies
# ---------------------------------------------------------------------------
step "Checking dependencies..."

DEPS=(jq git)
$WANT_CRON && DEPS+=(claude)   # claude -p is only used by the cron trigger
for cmd in "${DEPS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "      ERROR: '$cmd' not found on PATH - install it and retry."
        exit 1
    fi
done
echo "      ${DEPS[*]} - OK"

# ---------------------------------------------------------------------------
# 2. Init claude-meta repo
# ---------------------------------------------------------------------------
step "Setting up claude-meta repo..."

for dir in daily-summaries lessons-learned; do
    mkdir -p "$META_DIR/$dir"
done

if [[ ! -d "$META_DIR/.git" ]]; then
    git -C "$META_DIR" init -q
    for dir in daily-summaries lessons-learned; do
        touch "$META_DIR/$dir/.gitkeep"
        git -C "$META_DIR" add "$dir/.gitkeep"
    done
    git -C "$META_DIR" commit -q -m "init"
    echo "      Created and initialised: $META_DIR"
else
    for dir in daily-summaries lessons-learned; do
        [[ ! -f "$META_DIR/$dir/.gitkeep" ]] && touch "$META_DIR/$dir/.gitkeep"
    done
    echo "      Already exists - ensured subdirs present."
fi

# ---------------------------------------------------------------------------
# 3. Write env file (used by triggers running under cron)
# ---------------------------------------------------------------------------
step "Writing env file..."

mkdir -p "$HOME/.claude"
if ! grep -q "C4_CLAUDE_META_DIR" "$ENV_FILE" 2>/dev/null; then
    echo "export C4_CLAUDE_META_DIR=\"$META_DIR\"" >> "$ENV_FILE"
    echo "      Written: $ENV_FILE"
else
    # Update existing entry
    sed -i "s|^export C4_CLAUDE_META_DIR=.*|export C4_CLAUDE_META_DIR=\"$META_DIR\"|" "$ENV_FILE"
    echo "      Updated: $ENV_FILE"
fi

# Also add to ~/.bashrc for interactive shells if not already there
for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && ! grep -q "C4_CLAUDE_META_DIR" "$rc"; then
        echo "export C4_CLAUDE_META_DIR=\"$META_DIR\"" >> "$rc"
        echo "      Added C4_CLAUDE_META_DIR to $rc"
    fi
done

# ---------------------------------------------------------------------------
# 4. Install scripts
# ---------------------------------------------------------------------------
step "Installing files..."

mkdir -p "$SCRIPTS_DIR"

# git-sync and VERSION are shared by both mechanisms.
GIT_SYNC_SRC="$HERE/../git-sync/git-sync.sh"
if [[ -f "$GIT_SYNC_SRC" ]]; then
    cp "$GIT_SYNC_SRC" "$SCRIPTS_DIR/git-sync.sh"
    chmod +x "$SCRIPTS_DIR/git-sync.sh"
    echo "      $SCRIPTS_DIR/git-sync.sh"
else
    echo "      WARNING: git-sync.sh not found - run git-sync/install.sh manually."
fi

VERSION_SRC="$HERE/../VERSION"
[[ -f "$VERSION_SRC" ]] && cp "$VERSION_SRC" "$SCRIPTS_DIR/VERSION" && echo "      $SCRIPTS_DIR/VERSION"

# ---- Cron mechanism: prompt + trigger ----
if $WANT_CRON; then
    cp "$HERE/daily-summary.md"          "$SCRIPTS_DIR/daily-summary.md"
    cp "$HERE/daily-summary-trigger.sh"  "$SCRIPTS_DIR/daily-summary-trigger.sh"
    chmod +x "$SCRIPTS_DIR/daily-summary-trigger.sh"
    echo "      $SCRIPTS_DIR/daily-summary.md"
    echo "      $SCRIPTS_DIR/daily-summary-trigger.sh"
fi

# ---- Skill mechanism: prepare script + interactive SKILL.md ----
if $WANT_SKILL; then
    cp "$HERE/daily-summary-prepare.sh"  "$SCRIPTS_DIR/daily-summary-prepare.sh"
    chmod +x "$SCRIPTS_DIR/daily-summary-prepare.sh"
    echo "      $SCRIPTS_DIR/daily-summary-prepare.sh"

    SKILL_SRC="$HERE/../skills/session-digest-daily-summary/SKILL.md"
    SKILL_DIR="$META_DIR/.claude/skills/session-digest-daily-summary"
    if [[ -f "$SKILL_SRC" ]]; then
        mkdir -p "$SKILL_DIR"
        cp "$SKILL_SRC" "$SKILL_DIR/SKILL.md"
        echo "      $SKILL_DIR/SKILL.md"
    else
        echo "      WARNING: skill not found at $SKILL_SRC - /session-digest-daily-summary will be unavailable."
    fi
fi

# ---- Write / update scheduler-config.json -----------------------------------
CONFIG_FILE="$SCRIPTS_DIR/scheduler-config.json"
cfg=$( [[ -f "$CONFIG_FILE" ]] && cat "$CONFIG_FILE" || echo '{}' )
cfg=$(echo "$cfg" | jq \
    --arg  time  "$SCHEDULE_TIME" \
    --argjson turns "$MIN_USER_TURNS" \
    --argjson chars "$MIN_TRANSCRIPT_CHARS" \
    '.dailySummary = {scheduleTime: $time, minUserTurns: $turns, minTranscriptChars: $chars}')
echo "$cfg" > "$CONFIG_FILE"
echo "      $CONFIG_FILE"

# ---------------------------------------------------------------------------
# 5. Register cron job
# ---------------------------------------------------------------------------
if $WANT_CRON; then
    step "Registering cron job..."

    CRON_CMD="$CRON_MIN $CRON_HOUR * * * '$SCRIPTS_DIR/daily-summary-trigger.sh' >> '$META_DIR/logs/daily-summary.log' 2>&1"
    mkdir -p "$META_DIR/logs"

    if crontab -l 2>/dev/null | grep -q "daily-summary-trigger.sh"; then
        echo "      Cron job already registered - skipping."
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo "      Registered: daily cron at $SCHEDULE_TIME"
    fi
fi

echo ""
echo "=== Install complete ==="
echo ""
echo "Open a new shell for C4_CLAUDE_META_DIR to take effect."

if $WANT_CRON; then
    echo "Logs: $META_DIR/logs/daily-summary.log"
    echo ""
    echo "--- Verify the cron scheduler ---"
    echo "  crontab -l | grep daily-summary"
    echo "  tail -f '$META_DIR/logs/daily-summary.log'"
    echo "  bash '$SCRIPTS_DIR/daily-summary-trigger.sh'   # test now"
fi

if $WANT_SKILL; then
    echo ""
    echo "--- Use the interactive skill ---"
    echo "  From inside Claude Code (run in $META_DIR): /session-digest-daily-summary"
fi
