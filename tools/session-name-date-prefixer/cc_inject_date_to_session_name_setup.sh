#!/usr/bin/env bash
# Combined install/uninstall for the claude session-name wrapper.
# Usage:
#   bash cc_inject_date_to_session_name_setup.sh            # install (default)
#   bash cc_inject_date_to_session_name_setup.sh install
#   bash cc_inject_date_to_session_name_setup.sh uninstall

set -euo pipefail

ACTION="${1:-install}"

BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/claude"
SOURCE="$(dirname "$(realpath "$0")")/cc_inject_date_to_session_name.sh"

install_wrapper() {
    # 1. Create bin dir
    if [[ ! -d "$BIN_DIR" ]]; then
        mkdir -p "$BIN_DIR"
        echo "Created $BIN_DIR"
    fi

    # 2. Copy wrapper
    cp -f "$SOURCE" "$WRAPPER"
    chmod +x "$WRAPPER"
    echo "Installed wrapper to $WRAPPER"

    # 3. Add to PATH in shell rc if not already present
    add_to_path() {
        local rc="$1"
        local line='export PATH="$HOME/.local/bin:$PATH"'
        if [[ -f "$rc" ]] && grep -qF "$HOME/.local/bin" "$rc"; then
            echo "$rc already contains \$HOME/.local/bin — skipped"
        else
            echo "" >> "$rc"
            echo "# Added by claude wrapper install" >> "$rc"
            echo "$line" >> "$rc"
            echo "Added PATH entry to $rc"
        fi
    }

    case "${SHELL##*/}" in
        zsh)  add_to_path "$HOME/.zshrc" ;;
        bash) add_to_path "$HOME/.bashrc" ;;
        *)    add_to_path "$HOME/.profile" ;;
    esac

    # 4. Check PATH order — warn if $BIN_DIR doesn't come before real claude
    current_claude=$(command -v claude 2>/dev/null || true)
    if [[ -n "$current_claude" && "$current_claude" != "$WRAPPER" ]]; then
        echo ""
        echo "WARNING: 'claude' currently resolves to: $current_claude"
        echo "         Make sure \$HOME/.local/bin appears before that in PATH."
    fi

    # 5. Verify the real claude binary exists
    real_claude=$(
        IFS=:
        for dir in $PATH; do
            candidate="$dir/claude"
            if [[ -x "$candidate" && "$(realpath "$candidate")" != "$(realpath "$WRAPPER")" ]]; then
                echo "$candidate"
                break
            fi
        done
    )

    if [[ -n "$real_claude" ]]; then
        echo "Real claude found at: $real_claude"
    else
        echo "WARNING: Real claude binary not found on PATH. Install Claude Code first."
    fi

    echo ""
    echo "Done. Restart your terminal or run: source ~/.${SHELL##*/}rc"
}

uninstall_wrapper() {
    # 1. Remove wrapper file (only if it is our wrapper, not the real claude)
    if [[ -f "$WRAPPER" ]]; then
        if grep -qF "auto-injects --name" "$WRAPPER" 2>/dev/null; then
            rm -f "$WRAPPER"
            echo "Removed wrapper $WRAPPER"
        else
            echo "WARNING: $WRAPPER does not look like our wrapper — skipped"
        fi
    else
        echo "Wrapper not found at $WRAPPER — skipped"
    fi

    # 2. Remove the PATH line added by the installer
    remove_from_path() {
        local rc="$1"
        if [[ -f "$rc" ]] && grep -qF "# Added by claude wrapper install" "$rc"; then
            # Delete the comment line and the export line that follows it
            sed -i.bak '/# Added by claude wrapper install/,+1d' "$rc"
            rm -f "$rc.bak"
            echo "Removed PATH entry from $rc"
        else
            echo "$rc has no installer PATH entry — skipped"
        fi
    }

    case "${SHELL##*/}" in
        zsh)  remove_from_path "$HOME/.zshrc" ;;
        bash) remove_from_path "$HOME/.bashrc" ;;
        *)    remove_from_path "$HOME/.profile" ;;
    esac

    echo ""
    echo "Done. Restart your terminal or run: source ~/.${SHELL##*/}rc"
}

case "$ACTION" in
    install)   install_wrapper ;;
    uninstall) uninstall_wrapper ;;
    *)
        echo "Unknown action: $ACTION (expected 'install' or 'uninstall')" >&2
        exit 1
        ;;
esac
