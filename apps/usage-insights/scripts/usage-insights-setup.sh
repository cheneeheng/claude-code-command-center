#!/usr/bin/env bash
# Install / uninstall usage-insights from this checkout (macOS, Linux).
#
# install:   moves a store from the old default ~/.usage-insights to
#            ~/.claude-command-center/usage-insights, builds the web frontend (bun),
#            installs the `usage-insights` command with `uv tool install --editable`, and
#            prints a crontab line for a daily export. The crontab itself is never edited.
# uninstall: removes the command. The store (usage.db) is kept.
#
# Usage: usage-insights-setup.sh install|uninstall
set -euo pipefail

action="${1:-install}"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
store_dir="${C4_USAGE_INSIGHTS_HOME:-$HOME/.claude-command-center/usage-insights}"
store_path="$store_dir/usage.db"
old_store_dir="$HOME/.usage-insights"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "'$1' is not on PATH. Install it from $2" >&2; exit 1; }
}

# The store is history that outlives Claude Code's transcript cleanup, so it is moved,
# never rebuilt, and never moved over an existing store.
move_old_store() {
  [ -z "${C4_USAGE_INSIGHTS_HOME:-}" ] && [ -d "$old_store_dir" ] || return 0
  if [ -e "$store_dir" ]; then
    echo "WARNING: both $old_store_dir and $store_dir exist; moved nothing. Merge or delete one by hand." >&2
    return 0
  fi
  mkdir -p "$(dirname "$store_dir")"
  mv "$old_store_dir" "$store_dir"
  echo "Moved the store from $old_store_dir to $store_dir"
}

case "$action" in
  install)
    require bun https://bun.sh/
    require uv https://docs.astral.sh/uv/
    move_old_store
    echo "[1] Building the web frontend..."
    (cd "$app_dir/web" && bun install --frozen-lockfile && bun run build)
    echo "[2] Installing the usage-insights command..."
    # --reinstall makes a re-run pick up dependency changes in libs/.
    uv tool install --editable "$app_dir" --reinstall
    bin_dir="$(uv tool dir --bin)"
    echo ""
    echo "Done. Run \`usage-insights\` to open the dashboard."
    echo "Store: $store_path"
    echo ""
    echo "For a daily export, add this line with \`crontab -e\`:"
    echo "0 12 * * * $bin_dir/usage-insights export"
    ;;
  uninstall)
    require uv https://docs.astral.sh/uv/
    # Not grep -q: exiting early could kill uv with SIGPIPE, which pipefail reports.
    if uv tool list | grep '^usage-insights ' >/dev/null; then
      uv tool uninstall usage-insights
    else
      echo "usage-insights command not installed, skipped."
    fi
    echo "Kept the store: $store_path"
    echo "Remove the usage-insights line from your crontab if you added one."
    ;;
  *)
    echo "usage: $0 install|uninstall" >&2
    exit 2
    ;;
esac
