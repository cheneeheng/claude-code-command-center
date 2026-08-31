#!/usr/bin/env bash
# agents-workspace-sync-setup.sh - install / uninstall the agents-workspace-sync cron job
#
# What install does:
#   1. Ensures $C4_CLAUDE_META_DIR exists and exports it via ~/.profile if missing
#   2. Copies agents-workspace-sync.sh into <meta>/.claude/scripts/
#   3. Writes <meta>/.claude/scripts/agents-workspace-sync-config.json (repo list + time)
#   4. Installs a daily crontab entry
#
# Uninstall removes the crontab entry, the installed script, and (unless --keep-config)
# the config. The claude-meta repo, its logs, and every target repo are left untouched.
#
# Usage:
#   ./agents-workspace-sync-setup.sh                          # interactive install
#   ./agents-workspace-sync-setup.sh --action uninstall
#   ./agents-workspace-sync-setup.sh --non-interactive --repo /p/a/.agents_workspace

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTION="install"
SCHEDULE_TIME=""
META_DIR="${C4_CLAUDE_META_DIR:-$HOME/claude-meta}"
NON_INTERACTIVE=""
KEEP_CONFIG=""
REPOS=()

# The marker makes the crontab line ours to find and replace, without touching
# anything else the user has scheduled.
CRON_MARKER="# agents-workspace-sync"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)          ACTION="$2"; shift 2 ;;
        --repo)            REPOS+=("$2"); shift 2 ;;
        --time)            SCHEDULE_TIME="$2"; shift 2 ;;
        --meta-dir)        META_DIR="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --keep-config)     KEEP_CONFIG=1; shift ;;
        -h|--help)         sed -n '2,20p' "$0"; exit 0 ;;
        *)                 echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPTS_DIR="$META_DIR/.claude/scripts"
CONFIG_FILE="$SCRIPTS_DIR/agents-workspace-sync-config.json"
INSTALLED="$SCRIPTS_DIR/agents-workspace-sync.sh"

STEP=0
step() { STEP=$((STEP + 1)); printf '\033[33m[%s] %s\033[0m\n' "$STEP" "$1"; }
ok()   { printf '\033[32m      %s\033[0m\n' "$1"; }
warn() { printf '\033[31m      %s\033[0m\n' "$1"; }
dim()  { printf '\033[90m      %s\033[0m\n' "$1"; }

# ===========================================================================
# Uninstall
# ===========================================================================
if [[ "$ACTION" == "uninstall" ]]; then
    echo
    printf '\033[36m=== Agents Workspace Sync - Uninstall ===\033[0m\n'

    step "Removing crontab entry..."
    if crontab -l 2>/dev/null | grep -qF "$CRON_MARKER"; then
        crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" | crontab -
        ok "Removed the daily cron entry."
    else
        dim "Not installed - skipping."
    fi

    step "Removing installed files..."
    [[ -f "$INSTALLED" ]] && rm -f "$INSTALLED" && ok "Removed $INSTALLED"
    if [[ -z "$KEEP_CONFIG" && -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"; ok "Removed $CONFIG_FILE"
    elif [[ -n "$KEEP_CONFIG" ]]; then
        dim "Kept $CONFIG_FILE"
    fi

    echo
    printf '\033[36m=== Uninstall complete ===\033[0m\n'
    echo "Logs under $META_DIR/logs/ and every target repo were left untouched."
    exit 0
fi

# ===========================================================================
# Install
# ===========================================================================
echo
printf '\033[36m=== Agents Workspace Sync - Install ===\033[0m\n'
echo "Meta repo   : $META_DIR"
echo "Scripts dir : $SCRIPTS_DIR"
echo

command -v jq >/dev/null 2>&1 || { echo "jq is required (the worker reads its config with it)." >&2; exit 1; }

# ---- Settings ---------------------------------------------------------------
# 04:00 by default: after the digests (02:00 / 03:00) so the two automations never
# contend, and this one is not delayed by a long digest run.
if [[ -z "$SCHEDULE_TIME" ]]; then
    if [[ -n "$NON_INTERACTIVE" ]]; then
        SCHEDULE_TIME="04:00"
    else
        read -r -p "  Run time (HH:MM, 24h) [04:00]: " SCHEDULE_TIME
        SCHEDULE_TIME="${SCHEDULE_TIME:-04:00}"
    fi
fi
[[ "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || { echo "Invalid time: $SCHEDULE_TIME" >&2; exit 1; }

if [[ ${#REPOS[@]} -eq 0 ]]; then
    [[ -n "$NON_INTERACTIVE" ]] && { echo "--non-interactive needs at least one --repo." >&2; exit 1; }
    # Pre-fill from an existing config so re-running install is not a re-entry chore.
    if [[ -f "$CONFIG_FILE" ]]; then
        mapfile -t existing < <(jq -r '.repos[]? // empty' "$CONFIG_FILE")
        if [[ ${#existing[@]} -gt 0 ]]; then
            echo
            dim "Currently configured:"
            printf '        %s\n' "${existing[@]}"
            read -r -p "  Keep these? (y/n) [y]: " keep
            [[ -z "$keep" || "$keep" =~ ^[Yy] ]] && REPOS=("${existing[@]}")
        fi
    fi
    if [[ ${#REPOS[@]} -eq 0 ]]; then
        echo
        dim "Enter each .agents_workspace repo path; blank line to finish."
        dim "e.g. \$HOME/WorkLocal/00_Project/agent-skills/.agents_workspace"
        while true; do
            read -r -p "  Repo path: " p
            [[ -z "$p" ]] && break
            REPOS+=("${p%/}")
        done
    fi
fi
[[ ${#REPOS[@]} -gt 0 ]] || { echo "No repo paths given - nothing to install." >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Validating repo paths..."

# Warn now rather than let the first unattended run be the discovery. Each path must
# be its own repo top level; a path inside an outer repo is rejected at run time too.
BAD=0
for r in "${REPOS[@]}"; do
    p="${r%/}"
    if [[ ! -d "$p" ]]; then warn "MISSING : $p"; BAD=$((BAD + 1)); continue; fi
    # Same root test the worker uses: --show-prefix is empty only at a repo root.
    if ! prefix="$(git -C "$p" rev-parse --show-prefix 2>/dev/null)"; then
        warn "NOT A REPO : $p"; BAD=$((BAD + 1)); continue
    fi
    if [[ -n "$prefix" ]]; then
        warn "NESTED IN $(git -C "$p" rev-parse --show-toplevel 2>/dev/null) : $p"; BAD=$((BAD + 1)); continue
    fi
    ok "OK ($(git -C "$p" branch --show-current 2>/dev/null)) : $p"
done
[[ $BAD -gt 0 ]] && printf '\033[33m      %s path(s) will be logged as errors and skipped at run time.\033[0m\n' "$BAD"

# ---------------------------------------------------------------------------
step "Setting up claude-meta dir..."

mkdir -p "$SCRIPTS_DIR"
if [[ ! -d "$META_DIR/.git" ]]; then
    git -C "$META_DIR" init -q
    ok "Initialised git repo: $META_DIR"
else
    dim "$META_DIR already present."
fi

if [[ "${C4_CLAUDE_META_DIR:-}" != "$META_DIR" ]]; then
    if ! grep -q "C4_CLAUDE_META_DIR" "$HOME/.profile" 2>/dev/null; then
        echo "export C4_CLAUDE_META_DIR=\"$META_DIR\"" >> "$HOME/.profile"
        ok "Added C4_CLAUDE_META_DIR to ~/.profile"
    fi
    export C4_CLAUDE_META_DIR="$META_DIR"
fi

# ---------------------------------------------------------------------------
step "Installing files..."

cp "$HERE/agents-workspace-sync.sh" "$INSTALLED"
chmod +x "$INSTALLED"
ok "$INSTALLED"

[[ -f "$HERE/VERSION" ]] && cp "$HERE/VERSION" "$SCRIPTS_DIR/agents-workspace-sync.VERSION"

printf '%s\n' "${REPOS[@]}" \
    | jq -R . \
    | jq -s --arg t "$SCHEDULE_TIME" '{scheduleTime: $t, repos: .}' > "$CONFIG_FILE"
ok "$CONFIG_FILE (${#REPOS[@]} repo(s))"

# ---------------------------------------------------------------------------
step "Installing crontab entry..."

HH="${SCHEDULE_TIME%%:*}"
MM="${SCHEDULE_TIME##*:}"
# cron gives almost no environment; the worker aborts without C4_CLAUDE_META_DIR,
# so set it inline on the entry.
CRON_LINE="${MM#0} ${HH#0} * * * C4_CLAUDE_META_DIR=\"$META_DIR\" $INSTALLED >> \"$META_DIR/logs/agents-workspace-sync.log\" 2>&1 $CRON_MARKER"
mkdir -p "$META_DIR/logs"
{ crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; printf '%s\n' "$CRON_LINE"; } | crontab -
ok "Daily at $SCHEDULE_TIME"

echo
printf '\033[36m=== Install complete ===\033[0m\n'
echo "Logs: $META_DIR/logs/<yyyy>/<MM>/<timestamp>_agents-workspace-sync.log"
echo
printf '\033[33m--- Verify ---\033[0m\n'
echo "     $INSTALLED --dry-run     # show what each repo would do"
echo "     $INSTALLED               # run now"
echo "     crontab -l | grep agents-workspace-sync"
echo
echo "Edit the repo list any time: $CONFIG_FILE"
