#!/usr/bin/env bash
set -euo pipefail

# Smoke test for statusline-hook: install each variant with the real setup script into a
# throwaway config dir, then run the exact statusLine command it wrote to settings.json the
# way Claude Code does (through a shell) and assert the happy path: exit 0 and a statusline
# carrying the model and a rate-limit row. Uninstall must remove the key and the script.
# Needs pwsh (the setup script) and jq (the sh variant and reading settings.json).

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

for variant in ps1 sh; do
  dir="$WORK/$variant"
  pwsh -NoProfile -File "$HOOK_DIR/statusline-hook-setup.ps1" -Variant "$variant" -ClaudeDir "$dir" >/dev/null \
    || fail "$variant: setup install exited non-zero"
  cmd="$(jq -r '.statusLine.command' "$dir/settings.json")"
  out="$(bash -c "$cmd" < "$HOOK_DIR/fixtures/full.json")" || fail "$variant: hook exited non-zero"
  echo "$out" | grep -q "Opus 5.5" || fail "$variant: model missing from statusline"
  echo "$out" | grep -q "5h" || fail "$variant: 5h row missing"

  pwsh -NoProfile -File "$HOOK_DIR/statusline-hook-setup.ps1" -Action uninstall -ClaudeDir "$dir" >/dev/null \
    || fail "$variant: setup uninstall exited non-zero"
  [ "$(jq 'has("statusLine")' "$dir/settings.json")" = "false" ] || fail "$variant: statusLine key left behind"
  [ ! -e "$dir/statusline-hook.$variant" ] || fail "$variant: script left behind"
  echo "pass  $variant"
done

echo "PASS"
