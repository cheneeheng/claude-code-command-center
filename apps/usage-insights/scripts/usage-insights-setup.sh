#!/usr/bin/env bash
# Install / uninstall usage-insights from this checkout (macOS, Linux).
#
# install:   builds the web frontend (bun), installs the `usage-insights` command with
#            `uv tool install --editable`, and prints a crontab line for a daily export.
#            The crontab itself is never edited.
# uninstall: removes the command. The store (usage.db) is kept.
#
# Usage: usage-insights-setup.sh install|uninstall
set -euo pipefail

action="${1:-install}"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
store_path="${C4_USAGE_INSIGHTS_HOME:-$HOME/.usage-insights}/usage.db"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "'$1' is not on PATH. Install it from $2" >&2; exit 1; }
}

case "$action" in
  install)
    require bun https://bun.sh/
    require uv https://docs.astral.sh/uv/
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
    if uv tool list | grep -q '^usage-insights '; then
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
