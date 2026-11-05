#!/usr/bin/env bash
# agents-workspace-sync-setup.sh - install / uninstall the agents-workspace-sync cron job
#
# What install does:
#   1. Copies agents-workspace-sync.sh and VERSION into <install-dir>
#      (default ~/.claude-command-center/agents-workspace-sync/)
#   2. Writes <install-dir>/config.json (repo list + time)
#   3. Installs a daily crontab entry
#   4. Deletes the files an older version installed into <meta>/.claude/scripts/
#      (<meta> = $C4_CLAUDE_META_DIR, else ~/claude-meta)
#
# Uninstall removes the crontab entry, the installed script, and (unless --keep-config)
# the config. The logs under <install-dir>/logs/ and every target repo are left untouched.
#
# Usage:
#   ./agents-workspace-sync-setup.sh                          # interactive install
#   ./agents-workspace-sync-setup.sh --action uninstall
#   ./agents-workspace-sync-setup.sh --non-interactive --repo /p/a/.agents_workspace
#   ./agents-workspace-sync-setup.sh --install-dir /some/dir  # another install dir

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTION="install"
SCHEDULE_TIME=""
INSTALL_DIR="$HOME/.claude-command-center/agents-workspace-sync"
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
        --install-dir)     INSTALL_DIR="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --keep-config)     KEEP_CONFIG=1; shift ;;
        -h|--help)         sed -n '2,19p' "$0"; exit 0 ;;
        *)                 echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

CONFIG_FILE="$INSTALL_DIR/config.json"
INSTALLED="$INSTALL_DIR/agents-workspace-sync.sh"
VERSION_DST="$INSTALL_DIR/VERSION"

# Where versions up to 0.1.x installed, inside the claude-meta repo.
OLD_META="${C4_CLAUDE_META_DIR:-$HOME/claude-meta}"
OLD_SCRIPTS="$OLD_META/.claude/scripts"
OLD_CONFIG="$OLD_SCRIPTS/agents-workspace-sync-config.json"

STEP=0
step() { STEP=$((STEP + 1)); printf '\033[33m[%s] %s\033[0m\n' "$STEP" "$1"; }
ok()   { printf '\033[32m      %s\033[0m\n' "$1"; }
warn() { printf '\033[31m      %s\033[0m\n' "$1"; }
dim()  { printf '\033[90m      %s\033[0m\n' "$1"; }

remove_old_install() {
    local f found=""
    for f in agents-workspace-sync.sh agents-workspace-sync.VERSION agents-workspace-sync-config.json; do
        [[ -f "$OLD_SCRIPTS/$f" ]] || continue
        rm -f "$OLD_SCRIPTS/$f"; ok "Removed old $OLD_SCRIPTS/$f"; found=1
    done
    if [[ -n "$found" ]]; then
        dim "These were tracked in $OLD_META, whose git-sync commits the deletions."
    else
        dim "Nothing under $OLD_SCRIPTS."
    fi
}

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
    for f in "$INSTALLED" "$VERSION_DST"; do
        [[ -f "$f" ]] && rm -f "$f" && ok "Removed $f"
    done
    if [[ -z "$KEEP_CONFIG" && -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"; ok "Removed $CONFIG_FILE"
    elif [[ -n "$KEEP_CONFIG" ]]; then
        dim "Kept $CONFIG_FILE"
    fi

    step "Removing an older install..."
    remove_old_install

    echo
    printf '\033[36m=== Uninstall complete ===\033[0m\n'
    echo "Logs under $INSTALL_DIR/logs/ and every target repo were left untouched."
    exit 0
fi

# ===========================================================================
# Install
# ===========================================================================
echo
printf '\033[36m=== Agents Workspace Sync - Install ===\033[0m\n'
echo "Install dir : $INSTALL_DIR"
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
    # Pre-fill from an existing config, or the one an older version left in claude-meta,
    # so re-running install is not a re-entry chore.
    prev=""
    if [[ -f "$CONFIG_FILE" ]]; then prev="$CONFIG_FILE"; elif [[ -f "$OLD_CONFIG" ]]; then prev="$OLD_CONFIG"; fi
    if [[ -n "$prev" ]]; then
        mapfile -t existing < <(jq -r '.repos[]? // empty' "$prev")
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
step "Installing files..."

mkdir -p "$INSTALL_DIR"
cp "$HERE/agents-workspace-sync.sh" "$INSTALLED"
chmod +x "$INSTALLED"
ok "$INSTALLED"

[[ -f "$HERE/VERSION" ]] && cp "$HERE/VERSION" "$VERSION_DST"

printf '%s\n' "${REPOS[@]}" \
    | jq -R . \
    | jq -s --arg t "$SCHEDULE_TIME" '{scheduleTime: $t, repos: .}' > "$CONFIG_FILE"
ok "$CONFIG_FILE (${#REPOS[@]} repo(s))"

# ---------------------------------------------------------------------------
step "Installing crontab entry..."

HH="${SCHEDULE_TIME%%:*}"
MM="${SCHEDULE_TIME##*:}"
# The worker finds its config and log dir next to itself, so the entry needs no env.
# Replacing by marker also replaces the line an older version wrote.
CRON_LINE="${MM#0} ${HH#0} * * * \"$INSTALLED\" >> \"$INSTALL_DIR/cron.log\" 2>&1 $CRON_MARKER"
{ crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; printf '%s\n' "$CRON_LINE"; } | crontab -
ok "Daily at $SCHEDULE_TIME"

# ---------------------------------------------------------------------------
# After the cron entry points at the new worker, so a failure leaves the old one working.
step "Removing an older install..."
remove_old_install

echo
printf '\033[36m=== Install complete ===\033[0m\n'
echo "Logs: $INSTALL_DIR/logs/<yyyy>/<MM>/<timestamp>_agents-workspace-sync.log"
echo
printf '\033[33m--- Verify ---\033[0m\n'
echo "     $INSTALLED --dry-run     # show what each repo would do"
echo "     $INSTALLED               # run now"
echo "     crontab -l | grep agents-workspace-sync"
echo
echo "Edit the repo list any time: $CONFIG_FILE"
