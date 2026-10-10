#!/usr/bin/env bash
# Combined install/uninstall for the statusline-hook (bash twin of statusline-hook-setup.ps1).
# Copies the chosen script into the Claude config dir and wires it up as the
# `statusLine` command in settings.json (other keys are preserved). Needs jq.
# Usage:
#   ./statusline-hook-setup.sh                          # install sh variant (default)
#   ./statusline-hook-setup.sh --variant ps1            # PowerShell variant
#   ./statusline-hook-setup.sh uninstall
#   ./statusline-hook-setup.sh --claude-dir ~/claude    # override config dir
set -euo pipefail

usage() { sed -n '5,9p' "$0" | sed 's/^# //'; exit "${1:-0}"; }

action=install
variant=sh
claude_dir="$HOME/.claude"
while [ $# -gt 0 ]; do
  case "$1" in
    install|uninstall) action="$1" ;;
    --variant) variant="${2:?--variant needs sh or ps1}"; shift ;;
    --claude-dir) claude_dir="${2:?--claude-dir needs a path}"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
  shift
done
case "$variant" in sh|ps1) ;; *) echo "--variant must be sh or ps1" >&2; exit 1 ;; esac

command -v jq >/dev/null || { echo "jq is required (https://jqlang.org/)" >&2; exit 1; }

# Git Bash: write C:/... paths so the command also works for pwsh and outside Git Bash.
if command -v cygpath >/dev/null; then claude_dir="$(cygpath -m "$claude_dir")"; fi

settings="$claude_dir/settings.json"
script_name="statusline-hook.$variant"
dest="$claude_dir/$script_name"
source="$(cd "$(dirname "$0")" && pwd)/$script_name"

# Every script name an install of this hook has ever used, including the retired .py port.
known_scripts=(statusline-hook.ps1 statusline-hook.sh statusline-hook.py)

# Apply a jq filter to settings.json in place. A missing or blank file counts as {}.
edit_settings() {
  local current='{}'
  if [ -f "$settings" ] && [ -n "$(tr -d '[:space:]' < "$settings")" ]; then
    current="$(cat "$settings")"
  fi
  printf '%s' "$current" | jq "$@" > "$settings.tmp"
  mv "$settings.tmp" "$settings"
}

# Delete installed copies of this hook, except $1. Clears out other variants and the
# retired .py port so a reinstall leaves exactly one script behind.
remove_installed_scripts() {
  local name
  for name in "${known_scripts[@]}"; do
    [ "$name" = "$1" ] && continue
    if [ -e "$claude_dir/$name" ]; then
      rm -f "$claude_dir/$name"
      echo "Removed $claude_dir/$name"
    fi
  done
}

install_statusline() {
  [ -f "$source" ] || { echo "Hook script not found: $source" >&2; exit 1; }
  if [ ! -d "$claude_dir" ]; then
    mkdir -p "$claude_dir"
    echo "Created $claude_dir"
  fi

  cp -f "$source" "$dest"
  echo "Installed hook to $dest"
  remove_installed_scripts "$script_name"

  # The statusLine command Claude Code runs each turn. Prefer PowerShell 7, fall back to 5.1.
  local runner=bash
  if [ "$variant" = ps1 ]; then
    if command -v pwsh >/dev/null; then runner="pwsh -NoProfile -File"
    else runner="powershell -NoProfile -File"; fi
  fi
  local cmd="$runner \"$dest\""
  edit_settings --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd}'
  echo "Wired statusLine -> $cmd in $settings"
}

uninstall_statusline() {
  if [ ! -f "$settings" ]; then
    echo "$settings not found — skipped"
  elif [ -n "$(tr -d '[:space:]' < "$settings")" ] && jq -e 'has("statusLine")' "$settings" >/dev/null; then
    edit_settings 'del(.statusLine)'
    echo "Removed statusLine from $settings"
  else
    echo "No statusLine key in $settings — skipped"
  fi

  remove_installed_scripts ''
}

"${action}_statusline"
