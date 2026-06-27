#!/usr/bin/env bash
# setup.sh - interactive installer and uninstaller for scheduled-session-digests (Linux)
#
# Run from the repo root:
#   ./setup.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Helpers ----------------------------------------------------------------

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

prompt_confirm() {
    local label="$1"
    local default="${2:-y}"
    local hint
    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
    read -r -p "  $label $hint: " value || true
    value="${value:-$default}"
    [[ "$value" =~ ^[Yy] ]]
}

# ---- Banner -----------------------------------------------------------------

echo ""
echo "  scheduled-session-digests"
echo "  ─────────────────────────────────────────"
echo ""
echo "  [1]  Install"
echo "  [2]  Uninstall"
echo "  [Q]  Quit"
echo ""
read -r -p "  Choice: " choice || true
echo ""

case "${choice^^}" in
    1) mode="install"   ;;
    2) mode="uninstall" ;;
    Q) exit 0           ;;
    *)
        echo "  Invalid choice."
        exit 1
        ;;
esac

# =============================================================================
# INSTALL
# =============================================================================
if [[ "$mode" == "install" ]]; then

    # ---- Check dependencies -------------------------------------------------
    echo "  Checking dependencies..."
    for cmd in jq git claude; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "  ERROR: '$cmd' not found on PATH - install it and retry."
            exit 1
        fi
    done
    echo "  jq, git, claude - OK"
    echo ""

    # ---- Claude meta directory ----------------------------------------------
    default_meta="${CLAUDE_META_DIR:-$HOME/claude-meta}"
    META_DIR=$(prompt_input "Claude meta directory" "$default_meta")

    # ---- Validate / initialise git repo -------------------------------------
    if [[ -d "$META_DIR" ]]; then
        if [[ ! -d "$META_DIR/.git" ]]; then
            echo "  '$META_DIR' exists but is not a git repo."
            if prompt_confirm "  Initialise as git repo?"; then
                git -C "$META_DIR" init -q
                echo "  Initialised."
            else
                echo "  Aborted - the directory must be a git repo to continue."
                exit 1
            fi
        else
            echo "  Git repo found: $META_DIR"
        fi
    else
        echo "  '$META_DIR' does not exist."
        if prompt_confirm "  Create and initialise as git repo?"; then
            mkdir -p "$META_DIR"
            git -C "$META_DIR" init -q
            echo "  Created and initialised: $META_DIR"
        else
            echo "  Aborted."
            exit 1
        fi
    fi

    # ---- Persist CLAUDE_META_DIR --------------------------------------------
    export CLAUDE_META_DIR="$META_DIR"

    ENV_FILE="$HOME/.claude/claude-scheduler.env"
    mkdir -p "$HOME/.claude"
    if ! grep -q "CLAUDE_META_DIR" "$ENV_FILE" 2>/dev/null; then
        echo "export CLAUDE_META_DIR=\"$META_DIR\"" >> "$ENV_FILE"
    else
        sed -i "s|^export CLAUDE_META_DIR=.*|export CLAUDE_META_DIR=\"$META_DIR\"|" "$ENV_FILE"
    fi
    echo "  Set CLAUDE_META_DIR = $META_DIR"

    # ---- Which schedulers and mechanisms? -----------------------------------
    echo ""
    echo "  Which to install? (comma-separated, e.g. 1,2,3)"
    echo ""
    echo "  Skill-based (interactive, runs inside Claude Code, no claude -p):"
    echo "    [1]  daily-summary   (skill)"
    echo "    [2]  daily-lessons   (skill)"
    echo "    [3]  weekly-lessons  (skill)"
    echo "  Cron-based (cron + claude -p):"
    echo "    [4]  daily-summary   (cron)"
    echo "    [5]  daily-lessons   (cron)"
    echo "    [6]  weekly-lessons  (cron)"
    echo "    [7]  All of the above"
    echo ""
    sel=$(prompt_input "Choice" "1,2,3")

    ds_skill=false; dl_skill=false; wl_skill=false
    ds_cron=false;  dl_cron=false;  wl_cron=false
    IFS=',' read -ra picks <<< "$sel"
    for p in "${picks[@]}"; do
        case "${p// /}" in
            1) ds_skill=true ;;
            2) dl_skill=true ;;
            3) wl_skill=true ;;
            4) ds_cron=true ;;
            5) dl_cron=true ;;
            6) wl_cron=true ;;
            7) ds_skill=true; dl_skill=true; wl_skill=true; ds_cron=true; dl_cron=true; wl_cron=true ;;
            "") ;;
            *) echo "  Invalid choice: '$p'"; exit 1 ;;
        esac
    done

    # skill+cron -> both; otherwise the single chosen mechanism, or empty.
    mode_of() {
        if $1 && $2; then echo both
        elif $1;     then echo skill
        elif $2;     then echo cron
        else echo ""; fi
    }
    ds_mode=$(mode_of $ds_skill $ds_cron)
    dl_mode=$(mode_of $dl_skill $dl_cron)
    wl_mode=$(mode_of $wl_skill $wl_cron)

    if [[ -z "$ds_mode$dl_mode$wl_mode" ]]; then
        echo "  Nothing selected."
        exit 1
    fi

    echo ""

    # ---- Run installers -----------------------------------------------------
    if [[ -n "$ds_mode" ]]; then
        echo "  ── daily-summary ($ds_mode) ───────────────────────────"
        bash "$HERE/daily-summary/install.sh" "$ds_mode"
        echo ""
    fi

    if [[ -n "$dl_mode" ]]; then
        echo "  ── daily-lessons ($dl_mode) ───────────────────────────"
        bash "$HERE/daily-lessons/install.sh" "$dl_mode"
        echo ""
    fi

    if [[ -n "$wl_mode" ]]; then
        echo "  ── weekly-lessons ($wl_mode) ──────────────────────────"
        bash "$HERE/weekly-lessons/install.sh" "$wl_mode"
        echo ""
    fi

    echo "  ── Done ───────────────────────────────────────────────"
    echo ""
    echo "  Open a new shell for CLAUDE_META_DIR to take effect."
    if [[ -n "$wl_mode" ]]; then
        echo "  Edit '$META_DIR/.claude/scheduled-repos.json' to add your repos."
    fi
    echo ""
fi

# =============================================================================
# UNINSTALL
# =============================================================================
if [[ "$mode" == "uninstall" ]]; then

    META_DIR="${CLAUDE_META_DIR:-}"
    if [[ -z "$META_DIR" ]]; then
        META_DIR=$(prompt_input "claude-meta directory" "$HOME/claude-meta")
    fi
    SCRIPTS="$META_DIR/.claude/scripts"

    rm_file() {
        if [[ -f "$1" ]]; then rm -f "$1"; echo "  Removed: $1"; else echo "  Not found: $1"; fi
    }

    # ---- Cron-based mechanism (cron jobs + trigger + prompt files) ----------
    if prompt_confirm "Remove the cron-based schedulers (cron jobs + trigger scripts)?"; then
        CURRENT=$(crontab -l 2>/dev/null || true)
        NEW=$(echo "$CURRENT" \
            | grep -v "daily-summary-trigger.sh" \
            | grep -v "daily-lessons-trigger.sh" \
            | grep -v "weekly-lessons-trigger.sh" \
            || true)
        if [[ "$CURRENT" != "$NEW" ]]; then
            echo "$NEW" | crontab -
            echo "  Removed cron jobs."
        else
            echo "  No matching cron jobs found."
        fi

        for f in \
            "daily-summary.md"          "daily-summary-trigger.sh" \
            "daily-lessons.md"          "daily-lessons-trigger.sh" \
            "weekly-lessons.md"         "weekly-lessons-trigger.sh"
        do
            rm_file "$SCRIPTS/$f"
        done
    fi

    echo ""

    # ---- Skill-based mechanism (prepare scripts + interactive skills) -------
    if prompt_confirm "Remove the skill-based schedulers (prepare scripts + skills)?"; then
        for f in \
            "daily-summary-prepare.sh" \
            "daily-lessons-prepare.sh" \
            "weekly-lessons-prepare.sh"
        do
            rm_file "$SCRIPTS/$f"
        done

        for s in daily-summary daily-lessons weekly-lessons; do
            path="$META_DIR/.claude/skills/session-digest-$s"
            if [[ -d "$path" ]]; then
                rm -rf "$path"
                echo "  Removed: $path"
            else
                echo "  Not found: $path"
            fi
        done
    fi

    echo ""

    # ---- Shared files (used by both; remove only if you want a full clean) ---
    if prompt_confirm "Remove shared files (git-sync.sh, VERSION, scheduler-config.json)?" "n"; then
        for f in "git-sync.sh" "VERSION" "scheduler-config.json"; do
            rm_file "$SCRIPTS/$f"
        done
    fi

    echo ""
    echo "  Uninstall complete."
    echo ""
fi
