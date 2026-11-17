#!/usr/bin/env bash
# Export test: with C4_STATUSLINE_EXPORT on, a statusline command must overwrite
# <home>/.claude/statusline/latest/rate-limits.jsonl with one guard-readable line and print the
# same bytes as without it. Off, or with no rate_limits, it must write nothing.
#
#   bash tests/export.sh bash statusline-hook.sh
#   bash tests/export.sh pwsh -NoProfile -File statusline-hook.ps1
#
# HOME and USERPROFILE point at a temp dir, so the real reading is never touched.
set -uo pipefail

[ $# -gt 0 ] || { echo "usage: $0 <command...>" >&2; exit 2; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export TZ=UTC C4_STATUSLINE_NOW=1738400000 HOME="$WORK"
USERPROFILE="$WORK"
command -v cygpath >/dev/null && USERPROFILE="$(cygpath -w "$WORK")"
export USERPROFILE
FILE="$WORK/.claude/statusline/latest/rate-limits.jsonl"
PY="$(command -v python3 || command -v python)"
failed=0
fail() { echo "FAIL  $1"; failed=$((failed + 1)); }

jq '.session_id = "s1"' "$DIR/fixtures/full.json" > "$WORK/in.json"

# 1. On: one guard-readable line, and the same stdout as with the export off. Comparing the two
# runs, not fixtures/full.out, keeps this local-time-zone safe (PowerShell ignores TZ on Windows).
off="$(env -u C4_STATUSLINE_EXPORT "$@" < "$WORK/in.json"; echo "exit=$?")"
on="$(C4_STATUSLINE_EXPORT=1 "$@" < "$WORK/in.json"; echo "exit=$?")"
[ "$on" == "$off" ] || fail "stdout or exit code differs with the export on"
if [ -f "$FILE" ]; then
  [ "$(wc -l < "$FILE" | tr -d ' ')" = 1 ] || fail "file is not exactly one line"
  [ "$(head -c 1 "$FILE")" = "{" ] || fail "first byte is not { (BOM or UTF-16?)"
  ! grep -q $'\r' "$FILE" || fail "file contains \\r"
  # Parse exactly as usage-limit-watch.py does: UTF-8 text, json.loads per line.
  "$PY" -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1], encoding="utf-8").read().splitlines()]' \
    "$(command -v cygpath >/dev/null && cygpath -w "$FILE" || echo "$FILE")" || fail "python json.loads failed"
  [ "$(jq -c '.data.rate_limits' "$FILE")" = "$(jq -c '.rate_limits' "$WORK/in.json")" ] || fail "rate_limits differ"
  [ "$(jq -r '.session_id' "$FILE")" = s1 ] || fail "session_id is not s1"
  jq -e --argjson now "$(date +%s)" '(.ts / 1000 - $now) | fabs < 60' "$FILE" >/dev/null || fail "ts not within 60s of now in ms"
else
  fail "no file written with C4_STATUSLINE_EXPORT=1"
fi

# 2. A second run, any case of the value, still leaves one line.
C4_STATUSLINE_EXPORT=TRUE "$@" < "$WORK/in.json" >/dev/null
[ -f "$FILE" ] && [ "$(wc -l < "$FILE" | tr -d ' ')" = 1 ] || fail "second run did not leave exactly one line"

# 3. No rate_limits, or the variable unset: nothing written.
rm -rf "$WORK/.claude"
C4_STATUSLINE_EXPORT=1 "$@" < "$DIR/fixtures/no-rate-limits.json" >/dev/null
[ ! -e "$FILE" ] || fail "file written for a payload with no rate_limits"
unset C4_STATUSLINE_EXPORT
"$@" < "$WORK/in.json" >/dev/null
[ ! -e "$FILE" ] || fail "file written with C4_STATUSLINE_EXPORT unset"

[ "$failed" -eq 0 ] && echo PASS || { echo "$failed check(s) failed"; exit 1; }
