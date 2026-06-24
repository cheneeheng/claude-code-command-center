#!/usr/bin/env bash
# install.sh - git-sync utility
# Copies git-sync.sh to $CLAUDE_META_DIR/.claude/scripts/
# The daily-summary and weekly-lessons installers call this automatically.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="${CLAUDE_META_DIR:-$HOME/claude-meta}"
DEST="$META_DIR/.claude/scripts"

mkdir -p "$DEST"
cp "$HERE/git-sync.sh" "$DEST/git-sync.sh"
chmod +x "$DEST/git-sync.sh"

echo "Installed: $DEST/git-sync.sh"
