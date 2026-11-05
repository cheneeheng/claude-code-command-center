#!/usr/bin/env bash
# Install/uninstall the SessionStart hook that names each new session <folder>-<yyMMddHHmm>.
# The hook lives in settings.json; other keys and hooks are preserved. Needs jq.
# Usage:
#   bash session-name-date-prefixer-setup.sh                        # install (default)
#   bash session-name-date-prefixer-setup.sh uninstall
#   bash session-name-date-prefixer-setup.sh install --claude-dir /path/to/.claude

set -euo pipefail

action="install"
claude_dir="$HOME/.claude"
while [ $# -gt 0 ]; do
  case "$1" in
    install|uninstall) action="$1"; shift ;;
    --claude-dir) claude_dir="$2"; shift 2 ;;
    *) echo "Unknown argument: $1 (expected install, uninstall, --claude-dir <dir>)" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required (https://jqlang.org/)" >&2; exit 1; }

settings="$claude_dir/settings.json"
marker="session-name-date-prefixer"

# Prints nothing when the session already has a title (--name, /rename). The leading
# no-op names the tool, so install and uninstall can find this hook.
# shellcheck disable=SC2016  # expanded by the hook's shell, not here
cmd=': session-name-date-prefixer; grep -q '\''"session_title"'\'' || printf '\''{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"%s-%s"}}'\'' "$(basename "$PWD" | tr -c '\''A-Za-z0-9_\n-'\'' '\''-'\'')" "$(date +%y%m%d%H%M)"'

# The retired PATH wrapper this hook replaces.
old_wrapper="$HOME/.local/bin/claude"

# Apply a jq filter to settings.json in place. A missing or blank file counts as {}.
edit_settings() {
  local current='{}'
  if [ -f "$settings" ] && [ -n "$(tr -d '[:space:]' < "$settings")" ]; then
    current="$(cat "$settings")"
  fi
  printf '%s' "$current" | jq --arg m "$marker" "$@" > "$settings.tmp"
  mv "$settings.tmp" "$settings"
}

# SessionStart groups that are not ours.
others='[(.hooks.SessionStart // [])[] | select(any(.hooks[]?; (.command // "") | contains($m)) | not)]'

# The old wrapper is removed only when it is ours. The rc line that put ~/.local/bin on
# PATH stays: other tools, the native claude install among them, live there too.
remove_old_wrapper() {
  if [ -f "$old_wrapper" ] && grep -qF "auto-injects --name" "$old_wrapper"; then
    rm -f "$old_wrapper"
    echo "Removed the old wrapper $old_wrapper"
  fi
}

install_hook() {
  mkdir -p "$claude_dir"
  edit_settings --arg cmd "$cmd" \
    ".hooks.SessionStart = ($others + [{matcher: \"startup|clear\", hooks: [{type: \"command\", command: \$cmd}]}])"
  echo "Added the SessionStart hook to $settings"
  remove_old_wrapper
}

uninstall_hook() {
  if [ ! -f "$settings" ] || [ -z "$(tr -d '[:space:]' < "$settings")" ]; then
    echo "$settings not found, skipped"
  elif jq -e --arg m "$marker" "($others | length) < ((.hooks.SessionStart // []) | length)" "$settings" >/dev/null; then
    edit_settings "$others as \$o
      | if (\$o | length) > 0 then .hooks.SessionStart = \$o else del(.hooks.SessionStart) end
      | if .hooks == {} then del(.hooks) else . end"
    echo "Removed the SessionStart hook from $settings"
  else
    echo "No session-name hook in $settings, skipped"
  fi
  remove_old_wrapper
}

case "$action" in
  install)   install_hook ;;
  uninstall) uninstall_hook ;;
esac
