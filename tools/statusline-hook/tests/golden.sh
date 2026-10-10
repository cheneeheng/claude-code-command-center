#!/usr/bin/env bash
# Golden test: run a statusline command against every fixture and compare its stdout and
# exit code with the expected output. Both ports must pass the same fixtures unchanged.
#
#   bash tests/golden.sh bash statusline-hook.sh
#   bash tests/golden.sh pwsh -NoProfile -File statusline-hook.ps1
#
# fixtures/<case>.json is the stdin Claude Code would send; fixtures/<case>.out is the
# expected stdout with each ESC byte written as \e so the file stays readable. Reset times
# are pinned to UTC via TZ (PowerShell on Windows ignores TZ; see README).
set -uo pipefail

[ $# -gt 0 ] || { echo "usage: $0 <command...>" >&2; exit 2; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export TZ=UTC
failed=0

for input in "$DIR"/fixtures/*.json; do
  case="$(basename "$input" .json)"
  actual="$("$@" < "$input" | sed 's/\x1b/\\e/g'; echo "exit=${PIPESTATUS[0]}")"
  expected="$(cat "$DIR/fixtures/$case.out"; echo "exit=0")"
  if [ "$actual" == "$expected" ]; then
    echo "pass  $case"
  else
    echo "FAIL  $case"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/      /'
    failed=$((failed + 1))
  fi
done

[ "$failed" -eq 0 ] && echo "all fixtures pass" || { echo "$failed fixture(s) failed"; exit 1; }
