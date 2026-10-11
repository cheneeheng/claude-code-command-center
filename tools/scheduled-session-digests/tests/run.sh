#!/usr/bin/env bash
# Test harness. Usage: bash tests/run.sh <bash|pwsh> [suite]
# Suites: archive, equivalence (more arrive with later phases). Default: all.
#
# Each environment is a throwaway meta repo (its path contains a space) laid out
# the way install leaves it, plus a copy of the synthetic fixtures as the
# Claude Code data dir. Fixtures are synthetic on purpose: this repo is public.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MEMBER="$(cd "$HERE/.." && pwd)"
SHELL_UT="${1:?usage: run.sh <bash|pwsh> [suite]}"
SUITE="${2:-all}"
JQ=(jq); jq --binary -n 1 >/dev/null 2>&1 && JQ=(jq --binary)
NOW="$(date +%s)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $*"; }
check() { local msg="$1"; shift; if "$@"; then ok; else bad "$msg"; fi; }
eq()  { [[ "$1" == "$2" ]] || { bad "$3 (expected [$2], got [$1])"; return; }; ok; }

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
encode() { native "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

# new_env <dir>: sets META and FX for one throwaway environment.
new_env() {
  local base="$1" f off
  META="$base/my meta_dir"; FX="$base/fx"
  mkdir -p "$META/.claude/session-lessons/state" "$FX"
  cp -R "$HERE/fixtures/claude" "$HERE/fixtures/claude_devcontainer" "$FX/"
  # The meta repo's own sessions live in the project folder named after it.
  mkdir -p "$FX/claude/projects/$(encode "$META")"
  cp "$HERE/fixtures/meta-session.jsonl" \
     "$FX/claude/projects/$(encode "$META")/77777777-7777-4777-8777-777777777777.jsonl"
  long_session > "$FX/claude/projects/-home-dev-proj-alpha/99999999-9999-4999-8999-999999999999.jsonl"
  while IFS=$'\t' read -r f off; do touch -d "@$((NOW + off))" "$FX/$f"; done < "$HERE/fixtures/mtimes.tsv"
  for f in "$FX/claude/projects/$(encode "$META")"/*.jsonl \
           "$FX/claude/projects/-home-dev-proj-alpha/99999999-9999-4999-8999-999999999999.jsonl"; do
    touch -d "@$((NOW - 172800))" "$f"
  done
  cp -R "$MEMBER/src" "$META/.claude/session-lessons/src"
  cat > "$META/.claude/session-lessons/config.json" <<'EOF'
{
  "schedule": { "dailyAt": "03:00", "weeklyDay": "Sunday", "weeklyAt": "04:00" },
  "thresholds": { "minUserTurns": 2, "minTranscriptChars": 50 },
  "firstRunDays": 7, "maxSessionsPerRun": 20, "maxAttempts": 3, "settleMinutes": 60,
  "weeklyBatchChars": 400000
}
EOF
  "${JQ[@]}" -n --arg a "$(native "$FX/claude")" --arg b "$(native "$FX/claude_devcontainer")" \
    '{version: "test", scanRoots: [$a, $b]}' > "$META/.claude/session-lessons/state/install.json"
}

# A session with one assistant block of 10,005 code points: 9,999 'a', an emoji
# (two UTF-16 units) as the 10,000th, then five more. It must be cut after the
# emoji, never inside it.
long_session() {
  local body; body="$(printf 'a%.0s' $(seq 1 9999))"
  printf '%s\n' \
    '{"type":"user","cwd":"/home/dev/proj-alpha","message":{"role":"user","content":"Synthetic long request."}}' \
    "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"${body}😀tail5\"}]}}" \
    '{"type":"user","message":{"role":"user","content":"Second synthetic request."}}'
}

# run_ut <run args, Bash spelling>: runs the installed run script with the shell under test.
run_ut() {
  local args=() a
  if [[ "$SHELL_UT" == bash ]]; then
    bash "$META/.claude/session-lessons/src/run.sh" "$@"
  else
    for a in "$@"; do
      case "$a" in
        --archive-only) args+=(-ArchiveOnly) ;; --all) args+=(-All) ;;
        --since) args+=(-Since) ;; *) args+=("$a") ;;
      esac
    done
    pwsh -NoProfile -NonInteractive -File "$(native "$META/.claude/session-lessons/src/run.ps1")" "${args[@]}"
  fi
}

archived() { find "$META/transcripts" -type f -name "*_$1.md" 2>/dev/null | head -n 1; }
has_archive() { [[ -n "$(archived "$1")" ]]; }
no_archive()  { [[ -z "$(archived "$1")" ]]; }

# A process start time in the form the lock records for the shell under test.
start_time_of() {
  if [[ "$SHELL_UT" == bash ]]; then
    local ticks; ticks="$(sed 's/^.*) //' "/proc/$1/stat" | awk '{print $20}')"
    echo $(( $(awk '/^btime/ {print $2}' /proc/stat) + ticks / $(getconf CLK_TCK) ))
  else
    pwsh -NoProfile -Command "[DateTimeOffset]::new((Get-Process -Id $1).StartTime.ToUniversalTime()).ToUnixTimeSeconds()"
  fi
}
# The PID the shell under test sees for a background process.
pid_for_ut() {
  if [[ "$SHELL_UT" == pwsh && -r "/proc/$1/winpid" ]]; then cat "/proc/$1/winpid"; else echo "$1"; fi
}

suite_archive() {
  echo "suite archive ($SHELL_UT)"
  local T; T="$(mktemp -d)"; new_env "$T"

  # Default window: last 7 days, settled sessions only.
  local out; out="$(run_ut --archive-only)"; local rc=$?
  eq "$rc" 0 "archive-only exits 0"
  check "main session archived"                   has_archive 11111111-1111-4111-8111-111111111111
  check "devcontainer session archived"           has_archive 88888888-8888-4888-8888-888888888888
  check "project containing the meta name archived" has_archive 66666666-6666-4666-8666-666666666666
  check "long session archived"                   has_archive 99999999-9999-4999-8999-999999999999
  check "one-turn session skipped"                no_archive  22222222-2222-4222-8222-222222222222
  check "injected text does not count as a turn"  no_archive  cccccccc-cccc-4ccc-8ccc-cccccccccccc
  check "session inside the settle window skipped" no_archive 33333333-3333-4333-8333-333333333333
  check "session older than 7 days skipped"       no_archive  44444444-4444-4444-8444-444444444444
  check "sidechain transcript skipped"            no_archive  55555555-5555-4555-8555-555555555555
  check "meta repo's own session skipped"         no_archive  77777777-7777-4777-8777-777777777777
  check "subagent transcript skipped"             no_archive  agent-a1
  check "no cursor file created" test ! -e "$META/.claude/session-lessons/state/daily.cursor"
  check "summary line printed" grep -q "Archived 4 session(s), skipped 2 (too short)." <<<"$out"

  # The main session's cleaned conversation matches the expected text exactly.
  local main; main="$(archived 11111111-1111-4111-8111-111111111111)"
  check "archive header has Cleanup: v1" grep -qx "Cleanup: v1" "$main"
  check "archive title kept as-is" grep -qxF 'Title: Fix: build/test <ci> "pipe" | ünïcode' "$main"
  check "archive project is the cwd leaf" grep -qx "Project: proj-alpha" "$main"
  check "conversation matches expected" \
    cmp -s <(sed -n '/^## Conversation$/,$p' "$main" | tail -n +3) "$HERE/fixtures/expected/11111111-conversation.md"
  check "archive has no CR" bash -c "! grep -q $'\r' \"\$1\"" _ "$main"

  # The long block is cut after 10,000 code points, keeping the emoji whole.
  local long; long="$(archived 99999999-9999-4999-8999-999999999999)"
  # jq counts code points; MSYS Bash would count UTF-16 units.
  local cut; cut="$(grep -m 1 '^aaaa' "$long")"
  eq "$("${JQ[@]}" -Rr 'endswith("a😀")' <<<"$cut")" true "long block cut after the emoji"
  eq "$("${JQ[@]}" -Rr 'length' <<<"$cut")" 10000 "long block is 10,000 code points"
  check "long block marked truncated" grep -qx '\[...truncated\]' "$long"
  check "tail after the cut dropped" bash -c "! grep -q tail5 \"\$1\"" _ "$long"

  # -Since reaches back to a given local date: 12 days covers the 10-day-old session.
  run_ut --archive-only --since "$(date -d "@$((NOW - 12 * 86400))" +%Y-%m-%d)" >/dev/null
  check "-Since archives the older session" has_archive 44444444-4444-4444-8444-444444444444
  rm -f "$(archived 44444444-4444-4444-8444-444444444444)"

  # -All reaches the old session; re-archiving overwrites in place.
  local before; before="$(archived 11111111-1111-4111-8111-111111111111)"
  run_ut --archive-only --all >/dev/null
  check "-All archives the old session" has_archive 44444444-4444-4444-8444-444444444444
  touch -d "@$((NOW - 40 * 86400))" "$FX/claude/projects/-home-dev-proj-alpha/11111111-1111-4111-8111-111111111111.jsonl"
  run_ut --archive-only --all >/dev/null
  eq "$(find "$META/transcripts" -name '*_11111111-*' | wc -l | tr -d ' ')" 1 "re-archive keeps one file"
  eq "$(archived 11111111-1111-4111-8111-111111111111)" "$before" "re-archive overwrites the existing path"
  check "-All still creates no cursor" test ! -e "$META/.claude/session-lessons/state/daily.cursor"

  # Lock: a live lock makes a second run exit 0 without touching anything.
  # (--all from here on: session 1111 was moved 40 days back above.)
  rm -rf "$META/transcripts"
  sleep 60 & local holder=$!
  local hp; hp="$(pid_for_ut "$holder")"
  printf '{"pid":%s,"startTime":%s}\n' "$hp" "$(start_time_of "$hp")" > "$META/.claude/session-lessons/state/run.lock"
  out="$(run_ut --archive-only --all)"; rc=$?
  eq "$rc" 0 "run under a live lock exits 0"
  check "live lock reported" grep -q "Another run is in progress" <<<"$out"
  check "live lock: nothing archived" test ! -d "$META/transcripts"

  # Same PID, different start time: stale, replaced.
  printf '{"pid":%s,"startTime":%s}\n' "$hp" "$(( $(start_time_of "$hp") - 3600 ))" > "$META/.claude/session-lessons/state/run.lock"
  run_ut --archive-only --all >/dev/null
  check "lock with a reused PID is replaced" has_archive 11111111-1111-4111-8111-111111111111
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null

  # Dead PID: stale, replaced.
  rm -rf "$META/transcripts"
  printf '{"pid":%s,"startTime":1}\n' 999999 > "$META/.claude/session-lessons/state/run.lock"
  run_ut --archive-only --all >/dev/null
  check "lock with a dead PID is replaced" has_archive 11111111-1111-4111-8111-111111111111
  check "lock released after the run" test ! -e "$META/.claude/session-lessons/state/run.lock"

  rm -rf "$T"
}

suite_equivalence() {
  echo "suite equivalence (bash vs pwsh)"
  local T; T="$(mktemp -d)"
  local saved="$SHELL_UT" s
  for s in bash pwsh; do
    SHELL_UT="$s"; new_env "$T/$s"; run_ut --archive-only --all >/dev/null
  done
  SHELL_UT="$saved"
  eq "$(find "$T/bash/my meta_dir/transcripts" -type f | wc -l | tr -d ' ')" 5 "bash archived 5 sessions"
  if diff -r "$T/bash/my meta_dir/transcripts" "$T/pwsh/my meta_dir/transcripts" >/dev/null; then ok
  else bad "archives differ between bash and pwsh"; diff -r "$T/bash/my meta_dir/transcripts" "$T/pwsh/my meta_dir/transcripts" | head -20; fi
  rm -rf "$T"
}

case "$SUITE" in
  archive) suite_archive ;;
  equivalence) suite_equivalence ;;
  all) suite_archive; [[ "$SHELL_UT" == bash ]] && suite_equivalence ;;
  *) echo "unknown suite: $SUITE" >&2; exit 2 ;;
esac

echo "passed $PASS, failed $FAIL"
(( FAIL == 0 ))
