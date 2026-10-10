#!/usr/bin/env bash
set -euo pipefail

# Smoke test for statusline-hook: install each variant with each real setup script (ps1 and sh)
# into a throwaway config dir, then run the exact statusLine command it wrote to settings.json
# the way Claude Code does (through a shell) and assert the happy path: exit 0 and a statusline
# carrying the model and a rate-limit row. Uninstall must remove the key and the script.
# Needs pwsh (the ps1 setup script and variant) and jq (the sh variant and reading settings.json).

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# setup <ps1|sh> <variant> <dir> <install|uninstall>: run one setup script with its own flags.
setup() {
  if [ "$1" = ps1 ]; then
    pwsh -NoProfile -File "$HOOK_DIR/statusline-hook-setup.ps1" -Variant "$2" -ClaudeDir "$3" -Action "$4"
  else
    bash "$HOOK_DIR/statusline-hook-setup.sh" "$4" --variant "$2" --claude-dir "$3"
  fi
}

for setup_script in ps1 sh; do
  for variant in ps1 sh; do
    label="setup.$setup_script/$variant"
    dir="$WORK/$setup_script-$variant"
    setup "$setup_script" "$variant" "$dir" install >/dev/null || fail "$label: setup install exited non-zero"
    cmd="$(jq -r '.statusLine.command' "$dir/settings.json")"
    out="$(bash -c "$cmd" < "$HOOK_DIR/fixtures/full.json")" || fail "$label: hook exited non-zero"
    echo "$out" | grep -q "Opus 5.5" || fail "$label: model missing from statusline"
    echo "$out" | grep -q "5h" || fail "$label: 5h row missing"

    setup "$setup_script" "$variant" "$dir" uninstall >/dev/null || fail "$label: setup uninstall exited non-zero"
    [ "$(jq 'has("statusLine")' "$dir/settings.json")" = "false" ] || fail "$label: statusLine key left behind"
    [ ! -e "$dir/statusline-hook.$variant" ] || fail "$label: script left behind"
    echo "pass  $label"
  done
done

echo "PASS"
