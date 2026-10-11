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

# The long Windows form (-l): PowerShell resolves 8.3 short names such as
# RUNNER~1 to their long form, so the tests must name paths the same way.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w -l "$1"; else printf '%s' "$1"; fi; }
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
  # A second, test-only extraction proves one call can carry several.
  echo "## Part: echo" > "$META/.claude/session-lessons/src/prompts/extract/echo.md"
  cat > "$META/.claude/session-lessons/config.json" <<'EOF'
{
  "schedule": { "dailyAt": "03:00", "weeklyDay": "Sunday", "weeklyAt": "04:00" },
  "thresholds": { "minUserTurns": 2, "minTranscriptChars": 50 },
  "firstRunDays": 7, "maxSessionsPerRun": 20, "maxAttempts": 3, "settleMinutes": 60,
  "weeklyBatchChars": 400000,
  "models": { "daily": { "model": "sonnet", "effort": "medium" },
              "weekly": { "model": "opus", "effort": "medium" } },
  "extractions": {
    "lessons": { "enabled": true, "prompt": "extract/lessons.md", "outputDir": "lessons-learned",
                 "weekly": { "prompt": "merge/lessons.md", "master": "master-lessons/MASTER_LESSONS_LEARNED.md" } },
    "echo": { "enabled": true, "prompt": "extract/echo.md", "outputDir": "echo-out" }
  }
}
EOF
  local fake
  if [[ "$SHELL_UT" == bash ]]; then
    cp "$HERE/fake-claude.sh" "$base/fake-claude.sh"; chmod +x "$base/fake-claude.sh"; fake="$base/fake-claude.sh"
  else
    cp "$HERE/fake-claude.ps1" "$base/fake-claude.ps1"; fake="$(native "$base/fake-claude.ps1")"
  fi
  "${JQ[@]}" -n --arg a "$(native "$FX/claude")" --arg b "$(native "$FX/claude_devcontainer")" --arg c "$fake" \
    '{version: "test", scanRoots: [$a, $b], claudePath: $c, claudeNoToolsArgs: ["--tools", ""]}' \
    > "$META/.claude/session-lessons/state/install.json"
  # What install does in Phase 4: a git repo with the tool's ignore lines.
  git -C "$META" init -q
  git -C "$META" config user.name test; git -C "$META" config user.email test@example.invalid
  git -C "$META" config commit.gpgsign false
  printf '%s\n' 'logs/*session-lessons-*' '.claude/session-lessons/state/' \
    '.claude/session-lessons/staging/' '.fake-claude/' > "$META/.gitignore"
}

# Gives the four sessions inside the default window distinct ages; 8888 and
# 9999 share one mtime second.
spread_mtimes() {
  local p="$FX/claude/projects"
  touch -d "@$((NOW - 5 * 86400))" "$p/-home-dev-proj-alpha/11111111-1111-4111-8111-111111111111.jsonl"
  touch -d "@$((NOW - 4 * 86400))" "$p/-home-dev-my-meta-dir-tools/66666666-6666-4666-8666-666666666666.jsonl"
  touch -d "@$((NOW - 3 * 86400))" "$FX/claude_devcontainer/projects/-workspace-app/88888888-8888-4888-8888-888888888888.jsonl"
  touch -d "@$((NOW - 3 * 86400))" "$p/-home-dev-proj-alpha/99999999-9999-4999-8999-999999999999.jsonl"
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
        --since) args+=(-Since) ;; --dry-run) args+=(-DryRun) ;; --yes) args+=(-Yes) ;;
        --scheduled) args+=(-Scheduled) ;; --job) args+=(-Job) ;; *) args+=("$a") ;;
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

U1=11111111-1111-4111-8111-111111111111; U4=44444444-4444-4444-8444-444444444444
U6=66666666-6666-4666-8666-666666666666; U8=88888888-8888-4888-8888-888888888888
U9=99999999-9999-4999-8999-999999999999; U2=22222222-2222-4222-8222-222222222222
U3=33333333-3333-4333-8333-333333333333

out_of()   { find "$META/$1" -type f -name "*_$2*.md" 2>/dev/null | head -n 1; }
has_out()  { [[ -n "$(out_of "$1" "$2")" ]]; }
no_out()   { [[ -z "$(out_of "$1" "$2")" ]]; }
calls()    { cat "$META/.fake-claude/calls.log" 2>/dev/null; }
clear_calls() { mkdir -p "$META/.fake-claude"; : > "$META/.fake-claude/calls.log"; }
cursor()   { tr -d '[:space:]' < "$META/.claude/session-lessons/state/daily.cursor"; }
lastrun()  { "${JQ[@]}" -r "$1" "$META/.claude/session-lessons/state/last-run-daily.json"; }
fake_ctl() { mkdir -p "$META/.fake-claude"; "$@"; }
mtime_of() { stat -c %Y "$1"; }
set_cfg()  { local t; t="$(mktemp)"; "${JQ[@]}" "$1" "$META/.claude/session-lessons/config.json" > "$t" && mv "$t" "$META/.claude/session-lessons/config.json"; }
# Replaces the installed finish with one that fails, to simulate a run that
# dies after staging.
crash_finish() {
  printf 'exit 1\n' > "$META/.claude/session-lessons/src/finish.sh"
  printf 'exit 1\n' > "$META/.claude/session-lessons/src/finish.ps1"
}
set_inst() { local t; t="$(mktemp)"; "${JQ[@]}" "$1" "$META/.claude/session-lessons/state/install.json" > "$t" && mv "$t" "$META/.claude/session-lessons/state/install.json"; }

suite_daily() {
  echo "suite daily ($SHELL_UT)"
  local T out rc; T="$(mktemp -d)"

  # A. A dry run on a first run writes nothing at all.
  new_env "$T/a"; spread_mtimes
  out="$(run_ut --dry-run)"; rc=$?
  eq "$rc" 0 "dry run exits 0"
  check "dry run previews 4 sessions" grep -q "Daily run: 4 session(s) to process" <<<"$out"
  check "dry run calls no claude" test ! -e "$META/.fake-claude/calls.log"
  check "dry run writes no cursor" test ! -e "$META/.claude/session-lessons/state/daily.cursor"
  check "dry run writes no log" test ! -d "$META/logs"
  check "dry run archives nothing" test ! -d "$META/transcripts"
  check "dry run leaves no staging" test ! -d "$META/.claude/session-lessons/staging"

  # B. A first real run.
  out="$(run_ut --yes)"; rc=$?
  eq "$rc" 0 "first run exits 0"
  local u; for u in $U1 $U6 $U8 $U9; do
    check "lessons written for ${u:0:4}" has_out lessons-learned "$u"
    check "echo written for ${u:0:4}" has_out echo-out "$u"
  done
  check "old session not processed" no_out lessons-learned "$U4"
  check "one-turn session not processed" no_out lessons-learned "$U2"
  check "settling session not processed" no_out lessons-learned "$U3"
  check "reserved-character title becomes the file name" \
    grep -qF "_${U1}_Fix__build_test__ci___pipe____ünïcode.md" <<<"$(out_of lessons-learned "$U1")"
  eq "$(calls | grep -c ': lessons echo$')" 4 "one call per session carries lessons and echo"
  check "lessons file is the fake's part, preamble dropped" \
    bash -c 'head -n 1 "$1" | grep -q "^# Lessons "' _ "$(out_of lessons-learned "$U1")"
  # The newest candidate is the skipped one-turn session (2 days old).
  eq "$(cursor)" "$(mtime_of "$FX/claude/projects/-home-dev-proj-alpha/$U2.jsonl")" "cursor moves past the newest candidate, skipped ones included"
  eq "$(lastrun .processed)" 4 "last run: processed"
  eq "$(lastrun .failed)" 0 "last run: failed"
  eq "$(lastrun .givenUp)" 0 "last run: given up"
  eq "$(lastrun .deferred)" 0 "last run: deferred"
  eq "$(lastrun .results.lessons.written)" 4 "last run: lessons written"
  eq "$(lastrun .trigger)" manual "last run: trigger"
  eq "$(lastrun .committed)" true "last run: committed"
  eq "$(lastrun .pushed)" false "last run: nothing pushed without a remote"
  eq "$(lastrun .error)" null "last run: no error"
  eq "$(git -C "$META" log --oneline | wc -l | tr -d ' ')" 1 "git-sync makes one commit"
  check "commit message names the job" bash -c 'git -C "$1" log -1 --format=%s | grep -q "^lessons(daily): "' _ "$META"
  check "a run log is written" bash -c 'ls "$1"/logs/*/*/*_session-lessons-daily.log >/dev/null' _ "$META"
  check "staging is removed" test ! -d "$META/.claude/session-lessons/staging"
  check "summary line printed" grep -q "^Done: 4 processed, 0 failed" <<<"$out"
  clear_calls; run_ut --yes >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 0 "already-processed sessions are not sent again"
  # -Since later than the cursor never moves it.
  local before; before="$(cursor)"
  run_ut --since "$(date -d "@$NOW" +%Y-%m-%d)" --yes >/dev/null
  eq "$(cursor)" "$before" "-Since later than the cursor leaves it unchanged"

  # C. A first run writes its cutoff cursor before staging: a run that dies
  #    before finish (simulated by a finish that exits 1) leaves exactly that.
  new_env "$T/c0"; spread_mtimes; crash_finish
  run_ut --yes >/dev/null 2>&1
  local c; c="$(cursor)"
  check "first run wrote the 7-day cutoff cursor first" test $(( c - (NOW - 7 * 86400) )) -le 120 -a $(( (NOW - 7 * 86400) - c )) -le 120
  new_env "$T/c1"; spread_mtimes; crash_finish
  run_ut --all --yes >/dev/null 2>&1
  eq "$(cursor)" 0 "-All first run writes cursor 0 before staging"

  # claude fails: the run stops, records the error, counts nothing.
  new_env "$T/c"; spread_mtimes; fake_ctl touch "$META/.fake-claude/exit1"
  run_ut --yes >/dev/null; rc=$?
  check "failed run exits non-zero" test "$rc" -ne 0
  eq "$(cursor)" "$(( $(mtime_of "$FX/claude/projects/-home-dev-proj-alpha/$U1.jsonl") - 1 ))" "cursor stops before the first uncalled session"
  check "error recorded" bash -c '[[ "$1" == "claude exited 1"* ]]' _ "$(lastrun .error)"
  eq "$("${JQ[@]}" 'length' "$META/.claude/session-lessons/state/attempts.json" 2>/dev/null || echo 0)" 0 "no attempts counted"
  run_ut --yes >/dev/null; run_ut --yes >/dev/null
  check "three failed runs give up nothing" bash -c '[[ ! -s "$1" ]]' _ "$META/.claude/session-lessons/state/given-up.txt"
  rm -f "$META/.fake-claude/exit1"; clear_calls
  run_ut --yes >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 4 "uncalled sessions are staged again"

  # D. Leftover answers from a killed run are never read.
  new_env "$T/d"; spread_mtimes
  mkdir -p "$META/.claude/session-lessons/staging/daily/out"
  "${JQ[@]}" -n --arg u "$U1" '{job: "daily", writeCursor: false, cursorEpoch: 0, deferred: 0,
    jobs: [{uuid: $u, mtime: 1, exit: 0, needed: ["lessons"], outputs: {lessons: "lessons-learned/leftover.md"}}]}' \
    > "$META/.claude/session-lessons/staging/daily/manifest.json"
  printf '<<<extraction:lessons>>>\n# Lessons \xe2\x80\x94 x\n**Session**: %s\nLEFTOVER\n' "$U1" \
    > "$META/.claude/session-lessons/staging/daily/out/$U1.md"
  fake_ctl touch "$META/.fake-claude/exit1"
  run_ut --yes >/dev/null
  check "leftover answer never moved into place" test ! -e "$META/lessons-learned/leftover.md"

  # F. One part fails: the other is kept, the retry asks only for the missing one,
  #    and after 3 invalid answers it is given up and the cursor passes.
  new_env "$T/f"; spread_mtimes; fake_ctl bash -c "echo 'echo:$U1' > '$META/.fake-claude/fail.txt'"
  run_ut --yes >/dev/null
  check "lessons part kept when the echo part fails" has_out lessons-learned "$U1"
  check "failed echo part not written" no_out echo-out "$U1"
  eq "$(cursor)" "$(( $(mtime_of "$FX/claude/projects/-home-dev-proj-alpha/$U1.jsonl") - 1 ))" "cursor stops just before the failed session"
  clear_calls; run_ut --yes >/dev/null
  eq "$(calls)" "$U1: echo" "the retry asks only for echo"
  run_ut --yes >/dev/null
  check "echo given up after 3 invalid answers" grep -qx "echo:$U1" "$META/.claude/session-lessons/state/given-up.txt"
  eq "$(cursor)" "$(mtime_of "$FX/claude/projects/-home-dev-proj-alpha/$U2.jsonl")" "cursor passes the given-up session"
  eq "$(lastrun .givenUp)" 1 "last run: given up counted"

  # G. A session that already has lessons asks only for echo.
  new_env "$T/g"; spread_mtimes
  mkdir -p "$META/lessons-learned/2026/01"; touch "$META/lessons-learned/2026/01/2026-01-01_${U6}_old.md"
  run_ut --yes >/dev/null
  eq "$(calls | grep "^$U6:")" "$U6: echo" "a session with lessons asks only for echo"

  # H. Same-second pair: when one fails, the re-run still stages it.
  new_env "$T/h"; spread_mtimes; fake_ctl bash -c "echo 'lessons:$U9' > '$META/.fake-claude/fail.txt'"
  run_ut --yes >/dev/null
  check "the same-second partner succeeded" has_out lessons-learned "$U8"
  rm -f "$META/.fake-claude/fail.txt"; clear_calls
  run_ut --yes >/dev/null
  eq "$(calls)" "$U9: lessons" "the failed half of a same-second pair is staged again"

  # I. The cap: scheduled runs take the 2 oldest, never splitting a same-second
  #    group; the next run takes the rest. Manual runs ignore the cap.
  new_env "$T/i"; spread_mtimes; set_cfg '.maxSessionsPerRun = 2'
  run_ut --scheduled --job daily >/dev/null
  eq "$(calls | cut -d: -f1 | tr '\n' ' ')" "$U1 $U6 " "scheduled run stages the 2 oldest"
  eq "$(lastrun .deferred)" 2 "the rest is deferred"
  eq "$(lastrun .trigger)" scheduled "last run: trigger scheduled"
  clear_calls; run_ut --scheduled --job daily >/dev/null
  eq "$(calls | cut -d: -f1 | sort | tr '\n' ' ')" "$U8 $U9 " "the next run stages the same-second pair together"
  new_env "$T/j"; spread_mtimes; set_cfg '.maxSessionsPerRun = 2'
  run_ut --yes >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 4 "a manual run ignores the cap"

  # K. A missing claude is an error, not a silent no-op.
  new_env "$T/k"; spread_mtimes; set_inst '.claudePath = "/nonexistent/claude"'
  run_ut --yes >/dev/null 2>&1; rc=$?
  check "missing claude exits non-zero" test "$rc" -ne 0
  check "missing claude recorded" bash -c '[[ "$1" == "claude not found at "* ]]' _ "$(lastrun .error)"

  rm -rf "$T"
}

MASTER_REL="master-lessons/MASTER_LESSONS_LEARNED.md"
wcursor() { tr -d '[:space:]' < "$META/.claude/session-lessons/state/weekly-lessons.cursor"; }

# weekly_env <dir>: an environment with lessons files and a master, no sessions to digest.
# Files a, b, c (b and c share one mtime second), d, plus a stub, all inside 7 days.
weekly_env() {
  new_env "$1"
  local L="$META/lessons-learned/2026/10" d
  mkdir -p "$L" "$META/master-lessons"
  for d in a b c d; do
    printf '# Lessons \xe2\x80\x94 2026-10-0x\n**Session**: %s\n\n## Synthetic lesson %s\n\n**Lesson:** Rule %s.\n' "$d" "$d" "$d" > "$L/2026-10-01_$d.md"
  done
  printf '# Lessons \xe2\x80\x94 x\n**Session**: s\n\n_No lessons extracted from this session._\n' > "$L/2026-10-01_stub.md"
  touch -d "@$((NOW - 4 * 86400))" "$L/2026-10-01_a.md"
  touch -d "@$((NOW - 3 * 86400))" "$L/2026-10-01_b.md" "$L/2026-10-01_c.md"
  touch -d "@$((NOW - 2 * 86400))" "$L/2026-10-01_d.md"
  touch -d "@$((NOW - 1 * 86400))" "$L/2026-10-01_stub.md"
  printf '%s\n' '# Master Lessons Learned' '' 'Cross-project lessons harvested weekly from daily session notes.' \
    'Last updated: 2026-01-01' '' '## Tooling' '' '### Old tool lesson' '**Lesson**: OLD-BODY-MARKER.' '' \
    '## Claude Code & Agent Development' '' '### Old agent lesson' '**Lesson**: Old agent rule.' \
    > "$META/$MASTER_REL"
  git -C "$META" add -A >/dev/null; git -C "$META" commit -qm seed
}
master_sha() { sha256sum "$META/$MASTER_REL" | cut -c1-16; }

suite_weekly() {
  echo "suite weekly ($SHELL_UT)"
  local T before; T="$(mktemp -d)"
  local L="lessons-learned/2026/10"

  # The staged input: grouped titles, not the master's body; no stub.
  weekly_env "$T/a"
  printf 'exit 3\n' > "$META/.claude/session-lessons/src/finish-weekly.sh"
  printf 'exit 3\n' > "$META/.claude/session-lessons/src/finish-weekly.ps1"
  run_ut --job weekly --yes >/dev/null 2>&1
  local in="$META/.claude/session-lessons/staging/weekly-lessons/in/batch-0.md"
  check "weekly input has a run date" grep -q '^Run date: ' "$in"
  check "weekly input lists titles under their sections" \
    bash -c 'grep -qx "## Claude Code & Agent Development" "$1" && grep -qx "### Old agent lesson" "$1"' _ "$in"
  check "weekly input leaves out the master's body" bash -c '! grep -q OLD-BODY-MARKER "$1"' _ "$in"
  check "weekly input holds the new files" grep -qx '## Source: 2026-10-01_a.md' "$in"
  check "weekly input skips the stub" bash -c '! grep -q "_stub.md" "$1"' _ "$in"
  check "echo (no weekly entry) gets no weekly run" test ! -d "$META/.claude/session-lessons/staging/weekly-echo"

  # A valid default answer: added under Tooling, old titles kept, date updated.
  weekly_env "$T/b"
  run_ut --job weekly --yes >/dev/null; local rc=$?
  eq "$rc" 0 "weekly run exits 0"
  eq "$(calls)" "weekly: 2026-10-01_a.md" "one batch, one call"
  check "new lessons merged" grep -qx '### Weekly lesson from 2026-10-01_a.md' "$META/$MASTER_REL"
  check "old titles kept" bash -c 'grep -qx "### Old tool lesson" "$1" && grep -qx "### Old agent lesson" "$1"' _ "$META/$MASTER_REL"
  check "Last updated set to the run date" grep -qx "Last updated: $(date +%Y-%m-%d)" "$META/$MASTER_REL"
  eq "$(awk '/^## /{s=$0} /^### Weekly lesson from/{print s}' "$META/$MASTER_REL")" "## Tooling" "added under its category"
  eq "$(wcursor)" "$(mtime_of "$META/$L/2026-10-01_stub.md")" "weekly cursor passes the newest file, stub included"
  eq "$("${JQ[@]}" -r .results.lessons.written "$META/.claude/session-lessons/state/last-run-weekly.json")" 2 "last run: 2 lessons added"

  # A custom answer: an existing-only category, a new category, duplicates.
  weekly_env "$T/c"
  printf '%s\n' '## Claude Code & Agent Development' '### New agent lesson' '**Lesson**: x.' \
    '### New agent lesson' '**Lesson**: in-answer duplicate.' '### Old tool lesson' '**Lesson**: existing duplicate.' \
    '## Security' '### New security lesson' '**Lesson**: y.' > "$META/weekly-answer.tmp"
  fake_ctl mv "$META/weekly-answer.tmp" "$META/.fake-claude/weekly-answer.md"
  run_ut --job weekly --yes >/dev/null
  check "a category that exists only in the master is accepted" grep -qx '### New agent lesson' "$META/$MASTER_REL"
  eq "$(grep -cx '### New agent lesson' "$META/$MASTER_REL")" 1 "an in-answer duplicate is kept once"
  eq "$(grep -cx '### Old tool lesson' "$META/$MASTER_REL")" 1 "an existing title is not added again"
  check "a missing valid category is created" bash -c 'grep -qx "## Security" "$1" && grep -qx "### New security lesson" "$1"' _ "$META/$MASTER_REL"

  # Nothing new: master untouched, cursor advanced.
  weekly_env "$T/d"; before="$(master_sha)"
  fake_ctl bash -c "printf '_No new lessons._\n' > '$META/.fake-claude/weekly-answer.md'"
  run_ut --job weekly --yes >/dev/null
  eq "$(master_sha)" "$before" "no new lessons leaves the master byte-identical"
  eq "$(wcursor)" "$(mtime_of "$META/$L/2026-10-01_stub.md")" "no new lessons still advances the cursor"

  # A malformed answer: master untouched, cursor not moved past the batch.
  weekly_env "$T/e"; before="$(master_sha)"
  fake_ctl touch "$META/.fake-claude/weekly-bad"
  run_ut --job weekly --yes >/dev/null
  eq "$(master_sha)" "$before" "a malformed answer leaves the master byte-identical"
  local c; c="$(wcursor)"
  check "a malformed answer leaves the cursor before the batch" test "$c" -lt "$(mtime_of "$META/$L/2026-10-01_a.md")"

  # Batches: small limit, one batch per file except the same-second pair b+c.
  # The second batch fails: the run stops there, d is not sent; the next run
  # re-sends b+c, then d.
  weekly_env "$T/f"; set_cfg '.weeklyBatchChars = 50'
  fake_ctl bash -c "echo 2026-10-01_b.md > '$META/.fake-claude/weekly-bad'"
  run_ut --job weekly --yes >/dev/null
  eq "$(calls | tr '\n' '|')" "weekly: 2026-10-01_a.md|weekly: 2026-10-01_b.md|" "the run stops at the failed batch"
  eq "$(wcursor)" "$(mtime_of "$META/$L/2026-10-01_a.md")" "cursor moves only over the done batch"
  rm -f "$META/.fake-claude/weekly-bad"; clear_calls
  run_ut --job weekly --yes >/dev/null
  eq "$(calls | tr '\n' '|')" "weekly: 2026-10-01_b.md|weekly: 2026-10-01_d.md|" "the failed batch is re-sent, then the next"
  check "the same-second pair was one batch" bash -c '! grep -q "Weekly lesson from 2026-10-01_c.md" "$1"' _ "$META/$MASTER_REL"

  # claude failing in a weekly run is an error: non-zero exit, recorded.
  weekly_env "$T/x"; fake_ctl touch "$META/.fake-claude/exit1"
  run_ut --job weekly --yes >/dev/null 2>&1; rc=$?
  check "a failed weekly run exits non-zero" test "$rc" -ne 0
  check "weekly error recorded" bash -c '[[ "$(jq -r .error "$1")" == "claude exited 1"* ]]' _ "$META/.claude/session-lessons/state/last-run-weekly.json"

  # Give-up: a batch that fails 3 times is given up and passed.
  weekly_env "$T/g"; set_cfg '.weeklyBatchChars = 50'
  fake_ctl bash -c "echo 2026-10-01_a.md > '$META/.fake-claude/weekly-bad'"
  run_ut --job weekly --yes >/dev/null; run_ut --job weekly --yes >/dev/null; run_ut --job weekly --yes >/dev/null
  check "the batch is given up after 3 invalid answers" grep -qx "weekly-lessons:$L/2026-10-01_a.md" "$META/.claude/session-lessons/state/given-up.txt"
  check "the run after the give-up went on to the next batch" grep -qx '### Weekly lesson from 2026-10-01_b.md' "$META/$MASTER_REL"

  rm -rf "$T"
}

# --- cli -------------------------------------------------------------------------
# cli_env <dir>: fixtures as the Claude data dir, a fake claude first on PATH, and
# a meta dir that does not exist yet. Sets META, FX, CLI_OUT.
cli_env() {
  local base="$1" f off
  # The meta folder exists (empty) so its long Windows name can be resolved:
  # cygpath -l cannot expand an 8.3 path that does not exist yet.
  META="$base/my meta_dir"; FX="$base/fx"; mkdir -p "$FX" "$base/bin" "$META"
  cp -R "$HERE/fixtures/claude" "$HERE/fixtures/claude_devcontainer" "$FX/"
  mkdir -p "$FX/claude/projects/$(encode "$META")"
  cp "$HERE/fixtures/meta-session.jsonl" "$FX/claude/projects/$(encode "$META")/77777777-7777-4777-8777-777777777777.jsonl"
  long_session > "$FX/claude/projects/-home-dev-proj-alpha/$U9.jsonl"
  while IFS=$'\t' read -r f off; do touch -d "@$((NOW + off))" "$FX/$f"; done < "$HERE/fixtures/mtimes.tsv"
  touch -d "@$((NOW - 172800))" "$FX/claude/projects/$(encode "$META")"/*.jsonl
  spread_mtimes
  cp "$HERE/fake-claude.sh" "$base/bin/claude"; chmod +x "$base/bin/claude"
  cp "$HERE/fake-claude.ps1" "$base/bin/claude.ps1"
  CLI_PATH="$base/bin:$PATH"
  if [[ "$SHELL_UT" == pwsh ]]; then CLI_ROOTS="$(native "$FX/claude");$(native "$FX/claude_devcontainer")"
  else CLI_ROOTS="$FX/claude:$FX/claude_devcontainer"; fi
}
# cli_ut <command> <options, Bash spelling>: runs the CLI from the member folder.
cli_ut() {
  local args=() a
  if [[ "$SHELL_UT" == bash ]]; then
    PATH="$CLI_PATH" C4_CLAUDE_DIR="$CLI_ROOTS" bash "$MEMBER/lessons.sh" "$@" | tee -a "$CLI_OUT"
    return "${PIPESTATUS[0]}"
  fi
  for a in "$@"; do
    case "$a" in
      --meta-dir) args+=(-MetaDir) ;; --no-schedule) args+=(-NoSchedule) ;; --no-archive) args+=(-NoArchive) ;;
      --yes) args+=(-Yes) ;; --purge) args+=(-Purge) ;; --daily-at) args+=(-DailyAt) ;;
      --weekly-day) args+=(-WeeklyDay) ;; --weekly-at) args+=(-WeeklyAt) ;; --job) args+=(-Job) ;;
      --all) args+=(-All) ;; --dry-run) args+=(-DryRun) ;; --archive-only) args+=(-ArchiveOnly) ;;
      --scheduled) args+=(-Scheduled) ;; --since) args+=(-Since) ;; *) args+=("$a") ;;
    esac
  done
  PATH="$CLI_PATH" C4_CLAUDE_DIR="$CLI_ROOTS" pwsh -NoProfile -NonInteractive -File "$(native "$MEMBER/lessons.ps1")" "${args[@]}" | tee -a "$CLI_OUT"
  return "${PIPESTATUS[0]}"
}
H_() { echo "$META/.claude/session-lessons"; }
ijq() { "${JQ[@]}" -r "$1" "$(H_)/state/install.json"; }
set_inst2() { local t; t="$(mktemp)"; "${JQ[@]}" "$1" "$(H_)/state/install.json" > "$t" && mv "$t" "$(H_)/state/install.json"; }
set_cfg2()  { local t; t="$(mktemp)"; "${JQ[@]}" "$1" "$(H_)/config.json" > "$t" && mv "$t" "$(H_)/config.json"; }
hm() { date -d "@$1" +%H:%M; }
dayname() { LC_ALL=C date -d "@$1" +%A; }
tree_sha() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }

suite_cli() {
  echo "suite cli ($SHELL_UT)"
  local T rc out; T="$(mktemp -d)"; CLI_OUT="$T/cli-out.log"; : > "$CLI_OUT"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  local sched=(--no-schedule)

  # A. A fresh install.
  cli_env "$T/a"
  cli_ut install --meta-dir "$META" "${sched[@]}" --yes >/dev/null; rc=$?
  eq "$rc" 0 "install exits 0"
  check "install creates a git repo" test -d "$META/.git"
  check "install writes config.json" test -f "$(H_)/config.json"
  check "install copies the scripts" test -f "$(H_)/src/run.sh"
  eq "$(ijq '.claudeNoToolsArgs | join(" ")')" "--tools  --no-session-persistence" "install records the headless flags"
  check "install records the claude path" bash -c '[[ "$1" == *claude* ]]' _ "$(ijq .claudePath)"
  eq "$(ijq '.scanRoots | length')" 2 "install takes the scan roots from C4_CLAUDE_DIR"
  eq "$(grep -c 'session-lessons' "$META/.gitignore")" 3 "install adds 3 .gitignore lines"
  check "the one-time archive covers sessions on disk" has_archive "$U1"
  check "nothing ran yet: no daily cursor" test ! -e "$(H_)/state/daily.cursor"

  # B. status, after a first manual run, with a given-up entry and an error.
  cli_ut run --meta-dir "$META" --yes >/dev/null
  printf 'lessons:%s\n' "$U4" >> "$(H_)/state/given-up.txt"
  local t; t="$(mktemp)"; "${JQ[@]}" '.error = "claude exited 1: synthetic"' "$(H_)/state/last-run-daily.json" > "$t" && mv "$t" "$(H_)/state/last-run-daily.json"
  out="$(cli_ut status --meta-dir "$META")"
  check "status shows the schedule" grep -q '^Schedule: daily at 03:00, weekly on Sunday at 04:00\.$' <<<"$out"
  check "status shows the next daily run" grep -q '^Next daily run: ' <<<"$out"
  check "status shows the daily cursor as a date" grep -qE '^daily progress: up to [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\.$' <<<"$out"
  check "status shows the last run" grep -q '^Last daily run: ' <<<"$out"
  check "status shows the last error" grep -q 'Error: claude exited 1: synthetic' <<<"$out"
  check "status lists the given-up session" grep -q "lessons:$U4" <<<"$out"

  # C. Re-install keeps edits and the first install time.
  set_cfg2 '.maxSessionsPerRun = 7'
  local first; first="$(ijq .installedAt)"
  sleep 1
  cli_ut install --meta-dir "$META" "${sched[@]}" --no-archive --yes >/dev/null
  eq "$("${JQ[@]}" -r .maxSessionsPerRun "$(H_)/config.json")" 7 "re-install keeps an edited value"
  eq "$(ijq .installedAt)" "$first" "re-install keeps the first installedAt"
  eq "$(grep -c 'session-lessons' "$META/.gitignore")" 3 "re-install adds no duplicate .gitignore lines"

  # D. Two meta dirs get two different scheduled entries.
  local name_a; name_a="$(ijq .taskName)"
  local keep_meta="$META"; META="$T/other meta"
  cli_ut install --meta-dir "$META" "${sched[@]}" --no-archive --yes >/dev/null
  check "two meta dirs get two different task names" test "$(ijq .taskName)" != "$name_a"
  META="$keep_meta"

  # E. A plain uninstall keeps the data and config.json.
  mkdir -p "$META/.claude/scripts" "$META/daily-summaries"
  echo foreign > "$META/.claude/scripts/agents-workspace-sync.ps1"; echo old > "$META/daily-summaries/a.md"
  cli_ut uninstall --meta-dir "$META" --yes >/dev/null; rc=$?
  eq "$rc" 0 "uninstall exits 0"
  check "uninstall keeps .git" test -d "$META/.git"
  check "uninstall keeps lessons" bash -c 'ls "$1"/lessons-learned/*/*/*.md >/dev/null' _ "$META"
  check "uninstall keeps the archive" has_archive "$U1"
  check "uninstall keeps config.json" test -f "$(H_)/config.json"
  check "uninstall keeps the logs" bash -c 'ls "$1"/logs/*/*/*session-lessons-*.log >/dev/null' _ "$META"
  check "uninstall removes src/ and state/" test ! -e "$(H_)/src" -a ! -e "$(H_)/state"
  eq "$(grep -c 'session-lessons' "$META/.gitignore")" 0 "uninstall removes its .gitignore lines"

  # F. -Purge removes exactly this tool's paths.
  cli_ut install --meta-dir "$META" "${sched[@]}" --no-archive --yes >/dev/null
  cli_ut uninstall --meta-dir "$META" --purge --yes >/dev/null
  check "purge removes lessons-learned/" test ! -e "$META/lessons-learned"
  check "purge removes transcripts/" test ! -e "$META/transcripts"
  check "purge removes .claude/session-lessons/" test ! -e "$(H_)"
  check "purge removes this tool's logs" bash -c '! ls "$1"/logs/*/*/*session-lessons-* >/dev/null 2>&1' _ "$META"
  check "a foreign file in .claude/scripts/ survives" test -f "$META/.claude/scripts/agents-workspace-sync.ps1"
  check "daily-summaries/ survives" test -f "$META/daily-summaries/a.md"
  check "the meta repo's .git survives" test -d "$META/.git"

  # G. Upgrading from the old tool.
  cli_env "$T/g"
  local S="$META/.claude/scripts" L="$META/lessons-learned/2026/10"
  mkdir -p "$S" "$META/.claude/skills/session-digest-daily-lessons" "$META/.claude/scheduled-session-digests/x" \
    "$META/daily-summaries" "$L" "$META/master-lessons"
  for f in daily-digest-trigger.ps1 daily-digest-prepare.sh git-sync.sh VERSION weekly-lessons.md; do echo old > "$S/$f"; done
  echo foreign > "$S/agents-workspace-sync.ps1"
  printf '{"dailyLessons":{"scheduleTime":"03:00","minUserTurns":2,"minTranscriptChars":50},"weeklyLessons":{"scheduleTime":"02:00","scheduleDayOfWeek":"Sunday"}}\n' > "$S/scheduler-config.json"
  echo "skill" > "$META/.claude/skills/session-digest-daily-lessons/SKILL.md"
  echo $((NOW - 6 * 86400)) > "$META/.claude/daily-lessons-cursor"
  echo $((NOW - 9 * 86400)) > "$META/.claude/weekly-lessons-cursor"
  echo 1 > "$META/.claude/daily-summary-cursor"; echo old > "$META/daily-summaries/a.md"; echo '{}' > "$META/.claude/settings.json"
  printf '# Lessons \xe2\x80\x94 x\n**Session**: %s\n\n## Old\n\n**Lesson:** Old.\n' "$U1" > "$L/2026-10-01_${U1}_old.md"
  printf '# Master Lessons Learned\n\nLast updated: 2026-01-01\n\n## Tooling\n\n### Old\n**Lesson**: Old.\n' > "$META/master-lessons/MASTER_LESSONS_LEARNED.md"
  git -C "$META" init -q; git -C "$META" add -A; git -C "$META" commit -qm old
  local lessons_sha; lessons_sha="$(tree_sha "$META/lessons-learned")$(tree_sha "$META/master-lessons")"
  out="$(cli_ut install --meta-dir "$META" "${sched[@]}" --yes)"
  check "the change list names what stays" bash -c 'grep -q "daily-summaries/" <<<"$1" && grep -q ".claude/settings.json" <<<"$1"' _ "$out"
  check "old script files removed" test ! -e "$S/daily-digest-trigger.ps1" -a ! -e "$S/git-sync.sh" -a ! -e "$S/scheduler-config.json"
  check "a foreign file in .claude/scripts/ stays" test -f "$S/agents-workspace-sync.ps1"
  check "old skills removed" test ! -e "$META/.claude/skills/session-digest-daily-lessons"
  check "old staging folder removed" test ! -e "$META/.claude/scheduled-session-digests"
  eq "$(tr -d '[:space:]' < "$(H_)/state/daily.cursor")" "$((NOW - 6 * 86400))" "the daily cursor is carried over"
  eq "$(tr -d '[:space:]' < "$(H_)/state/weekly-lessons.cursor")" "$((NOW - 9 * 86400))" "the weekly cursor is carried over"
  check "old cursors removed" test ! -e "$META/.claude/daily-lessons-cursor" -a ! -e "$META/.claude/weekly-lessons-cursor"
  eq "$("${JQ[@]}" -r .schedule.weeklyAt "$(H_)/config.json")" "02:00" "the old weekly time is carried over"
  eq "$("${JQ[@]}" -r .thresholds.minTranscriptChars "$(H_)/config.json")" 50 "the old thresholds are carried over"
  check "daily-summary-cursor and settings.json stay" test -f "$META/.claude/daily-summary-cursor" -a -f "$META/.claude/settings.json"
  eq "$(tree_sha "$META/lessons-learned")$(tree_sha "$META/master-lessons")" "$lessons_sha" "existing lessons and master byte-identical"
  check "the one-time archive covers an already-processed session" has_archive "$U1"
  fake_ctl true; clear_calls
  cli_ut run --meta-dir "$META" --yes >/dev/null
  check "the next run skips sessions that already have lessons" bash -c '! grep -q "^$1:" "$2"' _ "$U1" "$META/.fake-claude/calls.log"
  check "the next run processes the others" grep -q "^$U6:" "$META/.fake-claude/calls.log"

  # H. The due rule (run --scheduled through the CLI).
  cli_env "$T/h"
  cli_ut install --meta-dir "$META" "${sched[@]}" --no-archive --yes >/dev/null
  set_cfg2 ".schedule.dailyAt = \"$(hm $((NOW + 3600)))\" | .schedule.weeklyDay = \"$(dayname $((NOW + 86400)))\" | .thresholds.minTranscriptChars = 50"
  cli_ut run --meta-dir "$META" --scheduled >/dev/null
  check "nothing runs before the first dailyAt after install" test ! -e "$(H_)/state/last-run-daily.json"
  set_inst2 ".installedAt = $((NOW - 2 * 86400))"
  set_cfg2 ".schedule.dailyAt = \"$(hm $((NOW - 3600)))\" | .maxSessionsPerRun = 2"
  cli_ut run --meta-dir "$META" --dry-run >/dev/null; cli_ut run --meta-dir "$META" --archive-only >/dev/null
  check "-DryRun and -ArchiveOnly write no last-run file" test ! -e "$(H_)/state/last-run-daily.json"
  fake_ctl true; clear_calls
  cli_ut run --meta-dir "$META" --scheduled >/dev/null
  eq "$(lastrun .trigger)" scheduled "a due daily job runs (after a dry run)"
  check "the weekly job is not due" test ! -e "$(H_)/state/last-run-weekly.json"
  eq "$(lastrun .deferred)" 2 "the cap leaves a backlog"
  clear_calls; cli_ut run --meta-dir "$META" --scheduled >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 2 "the next tick drains the backlog"
  clear_calls; cli_ut run --meta-dir "$META" --scheduled >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 0 "a job whose run finished after its time is skipped"
  set_inst2 ".installedAt = $((NOW - 2 * 86400))"; rm -f "$(H_)/state/last-run-daily.json"
  cli_ut run --meta-dir "$META" --yes >/dev/null
  clear_calls; cli_ut run --meta-dir "$META" --scheduled >/dev/null
  eq "$(calls | wc -l | tr -d ' ')" 0 "a manual run counts as the day's run"
  # An outage on a tick with work to do: recorded, and retried at the next tick.
  rm -f "$META"/lessons-learned/*/*/*"$U6"*.md "$(H_)/state/last-run-daily.json"
  echo $((NOW - 7 * 86400)) > "$(H_)/state/daily.cursor"
  touch "$META/.fake-claude/exit1"
  cli_ut run --meta-dir "$META" --scheduled >/dev/null 2>&1
  check "an outage is recorded" bash -c '[[ "$(jq -r .error "$1")" != null ]]' _ "$(H_)/state/last-run-daily.json"
  rm -f "$META/.fake-claude/exit1"
  clear_calls; cli_ut run --meta-dir "$META" --scheduled >/dev/null
  check "the tick after an outage retries" grep -q "^$U6:" "$META/.fake-claude/calls.log"
  set_cfg2 ".schedule.weeklyDay = \"$(dayname $((NOW - 86400)))\" | .schedule.weeklyAt = \"00:01\""
  cli_ut run --meta-dir "$META" --scheduled >/dev/null
  check "a missed weekly day runs at the next tick" test -f "$(H_)/state/last-run-weekly.json"

  # Real scheduling, only in CI on the native pairs: a local test run never
  # registers anything. A dummy old-tool entry pointing at this meta repo must
  # be removed by install, which registers the new entry; uninstall removes it.
  if [[ "${CI:-}" == true && "$SHELL_UT" == pwsh && "${OS:-}" == Windows_NT ]]; then
    cli_env "$T/s"; mkdir -p "$META"
    local ps1="$T/sched.ps1"
    cat > "$ps1" <<'EOF'
param([string]$Mode, [string]$Meta, [string]$Name)
$f = '\ClaudeAutomation\scheduled-session-digests\'
if ($Mode -eq 'seed') {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-File `"$Meta\.claude\scripts\daily-digest-trigger.ps1`""
  Register-ScheduledTask -TaskPath $f -TaskName 'SessionDigest-DailyLessons' -Action $a -Trigger (New-ScheduledTaskTrigger -Daily -At '03:00') | Out-Null
} else { [bool](Get-ScheduledTask -TaskPath $f -TaskName $Name -ErrorAction SilentlyContinue) }
EOF
    pwsh -NoProfile -File "$(native "$ps1")" seed "$(native "$META")"
    cli_ut install --meta-dir "$META" --no-archive --yes >/dev/null
    local tn; tn="$(ijq .taskName | sed 's/.*\\//')"
    eq "$(pwsh -NoProfile -File "$(native "$ps1")" check "" "$tn")" True "CI: install registers the hourly task"
    eq "$(pwsh -NoProfile -File "$(native "$ps1")" check "" SessionDigest-DailyLessons)" False "CI: install removes the old task"
    cli_ut uninstall --meta-dir "$META" --yes >/dev/null
    eq "$(pwsh -NoProfile -File "$(native "$ps1")" check "" "$tn")" False "CI: uninstall removes the task"
  elif [[ "${CI:-}" == true && "$SHELL_UT" == bash && "$(uname -s)" == Linux ]]; then
    cli_env "$T/s"; mkdir -p "$META"
    { crontab -l 2>/dev/null || true; echo "0 3 * * * bash '$META/.claude/scripts/daily-digest-trigger.sh' daily-lessons"; } | crontab -
    cli_ut install --meta-dir "$META" --no-archive --yes >/dev/null
    check "CI: install adds the hourly cron entry" bash -c 'crontab -l | grep -qF "# session-lessons:$1"' _ "$META"
    check "CI: install removes the old cron line" bash -c '! crontab -l | grep -qF "daily-digest-trigger.sh"'
    cli_ut uninstall --meta-dir "$META" --yes >/dev/null
    check "CI: uninstall removes the cron entry" bash -c '! crontab -l 2>/dev/null | grep -qF "# session-lessons:$1"' _ "$META"
  fi

  # Every stdout line fits 80 columns (lines naming a path excepted: paths
  # cannot be wrapped).
  local wide; wide="$(grep -vF -e "$T" -e "$(native "$T")" -e "$MEMBER" "$CLI_OUT" | "${JQ[@]}" -Rr 'select(length > 80)' | head -3)"
  eq "$wide" "" "every CLI line fits 80 columns"

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

  # Daily: the same fixtures, one part failing, run twice in each shell.
  for s in bash pwsh; do
    SHELL_UT="$s"; new_env "$T/d$s"; spread_mtimes
    fake_ctl bash -c "echo 'echo:$U1' > '$META/.fake-claude/fail.txt'"
    run_ut --yes >/dev/null; run_ut --yes >/dev/null
  done
  SHELL_UT="$saved"
  local a="$T/dbash/my meta_dir" b="$T/dpwsh/my meta_dir" d
  for d in lessons-learned echo-out transcripts; do
    if diff -r "$a/$d" "$b/$d" >/dev/null; then ok; else bad "daily $d differs"; diff -r "$a/$d" "$b/$d" | head -10; fi
  done
  eq "$(cat "$b/.fake-claude/calls.log")" "$(cat "$a/.fake-claude/calls.log")" "daily: same calls in the same order"
  eq "$(cat "$b/.claude/session-lessons/state/daily.cursor")" "$(cat "$a/.claude/session-lessons/state/daily.cursor")" "daily: same cursor"
  eq "$("${JQ[@]}" -S . "$b/.claude/session-lessons/state/attempts.json")" "$("${JQ[@]}" -S . "$a/.claude/session-lessons/state/attempts.json")" "daily: same attempts"
  local norm='del(.startedAt, .finishedAt) | .'
  eq "$("${JQ[@]}" -S "$norm" "$b/.claude/session-lessons/state/last-run-daily.json")" \
     "$("${JQ[@]}" -S "$norm" "$a/.claude/session-lessons/state/last-run-daily.json")" "daily: same last-run summary"

  # Weekly: the same lessons files and master, small batches, a custom answer.
  for s in bash pwsh; do
    SHELL_UT="$s"; weekly_env "$T/w$s"; set_cfg '.weeklyBatchChars = 120'
    run_ut --job weekly --yes >/dev/null
  done
  SHELL_UT="$saved"
  a="$T/wbash/my meta_dir"; b="$T/wpwsh/my meta_dir"
  if cmp -s "$a/$MASTER_REL" "$b/$MASTER_REL"; then ok; else bad "weekly: master files differ"; diff "$a/$MASTER_REL" "$b/$MASTER_REL" | head -10; fi
  check "weekly: the master gained lessons" grep -q '^### Weekly lesson from' "$a/$MASTER_REL"
  check "weekly: several batches were compared" test "$(wc -l < "$a/.fake-claude/calls.log")" -ge 2
  eq "$(cat "$b/.fake-claude/calls.log")" "$(cat "$a/.fake-claude/calls.log")" "weekly: same batches in the same order"
  eq "$(cat "$b/.claude/session-lessons/state/weekly-lessons.cursor")" "$(cat "$a/.claude/session-lessons/state/weekly-lessons.cursor")" "weekly: same cursor"
  eq "$("${JQ[@]}" -S "$norm" "$b/.claude/session-lessons/state/last-run-weekly.json")" \
     "$("${JQ[@]}" -S "$norm" "$a/.claude/session-lessons/state/last-run-weekly.json")" "weekly: same last-run summary"
  rm -rf "$T"
}

case "$SUITE" in
  archive) suite_archive ;;
  daily) suite_daily ;;
  weekly) suite_weekly ;;
  cli) suite_cli ;;
  equivalence) suite_equivalence ;;
  all) suite_archive; suite_daily; suite_weekly; suite_cli; [[ "$SHELL_UT" == bash ]] && suite_equivalence ;;
  *) echo "unknown suite: $SUITE" >&2; exit 2 ;;
esac

echo "passed $PASS, failed $FAIL"
(( FAIL == 0 ))
