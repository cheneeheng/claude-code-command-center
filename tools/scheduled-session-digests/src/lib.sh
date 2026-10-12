# lib.sh: helpers shared by the Bash pipeline scripts. Sourced, never run.
#
# Cross-reference: src/lib.ps1 is the PowerShell twin. Keep both behaviourally
# identical (paths, encoding, lock format, cutoff rules).

if (( BASH_VERSINFO[0] < 4 )); then
  echo "session-lessons: Bash 4 or newer is required." >&2; exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "session-lessons: jq is required." >&2; exit 1; }

# Native jq on Windows turns \n into \r\n unless --binary is given; Linux jq has
# no such flag. All output must be LF.
JQ=(jq)
jq --binary -n 1 >/dev/null 2>&1 && JQ=(jq --binary)

# The meta repo is three levels above src/: <meta>/.claude/session-lessons/src.
SL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL_META="$(cd "$SL_SRC/../../.." && pwd)"
SL_HOME="$SL_META/.claude/session-lessons"
SL_STATE="$SL_HOME/state"
SL_CONFIG="$SL_HOME/config.json"
SL_INSTALL="$SL_STATE/install.json"

cfg()      { "${JQ[@]}" -r "$1" "$SL_CONFIG"; }
inst_get() { "${JQ[@]}" -r "$1" "$SL_INSTALL"; }

SL_STAGING="$SL_HOME/staging"

# Prints a line and, when a run log is open (SL_LOG, set from a script's --log
# argument, never exported), appends it there too.
SL_LOG=""
say() { printf '%s\n' "$*"; [[ -z "${SL_LOG:-}" ]] || printf '%s\n' "$*" >> "$SL_LOG"; }

# Rule 6: reserved filename characters and ASCII whitespace runs become '_'.
safe_title() { printf '%s' "$1" | LC_ALL=C sed -E 's/[\\/:*?"<>|]/_/g; s/[[:space:]]+/_/g'; }

# The categories src/prompts/merge/lessons.md offers. Keep the three in sync
# (this list, the prompt, and $script:LessonsCategories in lib.ps1).
LESSONS_CATEGORIES='["Architecture","Debugging","Performance","Security","Testing","Tooling","Workflow","API behaviour","Database","Other"]'
LESSONS_STUB="_No lessons extracted from this session._"

now_epoch() { date +%s; }

# Unix seconds, truncated, of a file's mtime.
mtime_epoch() { stat -c %Y "$1"; }

# Local yyyy-MM-dd of a Unix epoch.
local_date() { date -d "@$1" +%Y-%m-%d; }

# Claude Code names a project folder after the absolute path of its working
# directory, with every character that is not a letter or digit replaced by '-'.
# The path is the native one, so Windows paths are converted first, to their
# long form (an 8.3 short name such as RUNNER~1 is expanded, as PowerShell does).
encode_project_dir() {
  local p="$1"
  command -v cygpath >/dev/null 2>&1 && p="$(cygpath -w -l "$p")"
  printf '%s' "$p" | sed 's/[^A-Za-z0-9]/-/g'
}

# --- schedule and the due rule ------------------------------------------------
# epoch_at <epoch> <HH:MM>: that local day at that time.
epoch_at() { date -d "$(date -d "@$1" +%Y-%m-%d) $2" +%s; }

# The latest scheduled time at or before <now>: today's dailyAt or yesterday's;
# for weekly, the most recent weeklyDay at weeklyAt.
last_scheduled() {  # <job> <now>
  local at t d day
  if [[ "$1" == daily ]]; then
    at="$(cfg '.schedule.dailyAt')"; t="$(epoch_at "$2" "$at")"
    (( t > $2 )) && t="$(epoch_at "$(( $2 - 86400 ))" "$at")"
    echo "$t"; return
  fi
  at="$(cfg '.schedule.weeklyAt')"; day="$(cfg '.schedule.weeklyDay')"
  for d in 0 1 2 3 4 5 6 7; do
    t="$(epoch_at "$(( $2 - d * 86400 ))" "$at")"
    if (( t <= $2 )) && [[ "$(LC_ALL=C date -d "@$t" +%A)" == "$day" ]]; then echo "$t"; return; fi
  done
  echo 0
}

# The next scheduled time after <now>.
next_scheduled() {  # <job> <now>
  local last days=1 at; last="$(last_scheduled "$1" "$2")"
  at="$(cfg '.schedule.dailyAt')"
  [[ "$1" == weekly ]] && { days=7; at="$(cfg '.schedule.weeklyAt')"; }
  date -d "$(date -d "$(date -d "@$last" +%F) +$days day" +%F) $at" +%s
}

# A job is due when its latest scheduled time is later than both the install
# time and its last finished run, or its last run deferred sessions or ended
# with an error. -DryRun and -ArchiveOnly never write a last-run file.
job_due() {  # <job>
  local file="$SL_STATE/last-run-$1.json" base fin
  base="$(inst_get '.installedAt // 0')"
  if [[ -f "$file" ]]; then
    [[ -n "$("${JQ[@]}" -r '.error // empty' "$file")" ]] && return 0
    (( $("${JQ[@]}" -r '.deferred // 0' "$file") > 0 )) && return 0
    fin="$("${JQ[@]}" -r '.finishedAt // 0' "$file")"
    (( fin > base )) && base="$fin"
  fi
  (( $(last_scheduled "$1" "$(now_epoch)") > base ))
}

# --- lock ------------------------------------------------------------------
# state/run.lock is {"pid":N,"startTime":E}, E = the process start time as UTC
# Unix seconds, truncated. A lock is live when that PID exists and its start
# time matches within 1 second; anything else is stale and replaced.

proc_start_epoch() {
  local pid="$1" ticks btime hz
  [[ -r "/proc/$pid/stat" ]] || return 1
  # Field 22 counts from the end of the parenthesised command name, which may
  # itself contain spaces.
  ticks="$(sed 's/^.*) //' "/proc/$pid/stat" | awk '{print $20}')"
  btime="$(awk '/^btime/ {print $2}' /proc/stat)"
  hz="$(getconf CLK_TCK)"
  echo $(( btime + ticks / hz ))
}

lock_is_live() {
  local lock="$1" pid start actual
  pid="$("${JQ[@]}" -r '.pid // empty' "$lock" 2>/dev/null)" || return 1
  start="$("${JQ[@]}" -r '.startTime // empty' "$lock" 2>/dev/null)" || return 1
  [[ -n "$pid" && -n "$start" ]] || return 1
  actual="$(proc_start_epoch "$pid")" || return 1
  (( actual - start <= 1 && start - actual <= 1 ))
}

# Takes the lock or exits 0 when another run holds it.
acquire_lock() {
  local lock="$SL_STATE/run.lock" tmp
  mkdir -p "$SL_STATE"
  tmp="$(mktemp "$SL_STATE/.lock.XXXXXX")"
  printf '{"pid":%s,"startTime":%s}\n' "$$" "$(proc_start_epoch $$)" > "$tmp"
  if ! ln "$tmp" "$lock" 2>/dev/null; then
    if lock_is_live "$lock"; then
      rm -f "$tmp"
      echo "Another run is in progress (pid $("${JQ[@]}" -r .pid "$lock"))."
      exit 0
    fi
    rm -f "$lock"
    if ! ln "$tmp" "$lock" 2>/dev/null; then
      rm -f "$tmp"; echo "Another run is in progress."; exit 0
    fi
  fi
  rm -f "$tmp"
  trap 'rm -f "$SL_STATE/run.lock"' EXIT
}
