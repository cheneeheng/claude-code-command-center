#!/usr/bin/env bash
# lessons.sh: the session-lessons CLI for Linux. Run it from the clone.
#
#   install   [--meta-dir <p>] [--daily-at HH:MM] [--weekly-day <Day>] [--weekly-at HH:MM]
#             [--no-schedule] [--no-archive] [--yes]
#   run       [--meta-dir <p>] [run.sh options: --job, --all, --since, --dry-run, --yes, ...]
#   status    [--meta-dir <p>]
#   uninstall [--meta-dir <p>] [--purge] [--yes]
#
# --meta-dir defaults to $C4_CLAUDE_META_DIR, then ~/claude-meta.
# Cross-reference: lessons.ps1 is the Windows twin.

set -euo pipefail

MEMBER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="bash $MEMBER/lessons.sh"
die() { echo "lessons: $*" >&2; exit 1; }

(( BASH_VERSINFO[0] >= 4 )) || die "Bash 4 or newer is required."
command -v jq >/dev/null 2>&1 || die "jq is required (apt install jq)."
# Native jq on Windows writes \r\n unless --binary is given; Linux jq has no such
# flag. Every jq call below goes through this.
if command jq --binary -n 1 >/dev/null 2>&1; then jq() { command jq --binary "$@"; }; fi

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
META="${C4_CLAUDE_META_DIR:-$HOME/claude-meta}"
YES=0; PURGE=0; NOSCHED=0; NOARCH=0; DAILY_AT=""; WEEKLY_DAY=""; WEEKLY_AT=""; PASS=()
while (( $# )); do
  case "$1" in
    --meta-dir) META="$2"; shift 2 ;;
    --yes) YES=1; PASS+=("$1"); shift ;;
    --purge) PURGE=1; shift ;;
    --no-schedule) NOSCHED=1; shift ;;
    --no-archive) NOARCH=1; shift ;;
    --daily-at) DAILY_AT="$2"; shift 2 ;;
    --weekly-day) WEEKLY_DAY="$2"; shift 2 ;;
    --weekly-at) WEEKLY_AT="$2"; shift 2 ;;
    *) PASS+=("$1"); shift ;;
  esac
done
mkdir -p "$(dirname "$META")"
META="$(cd "$(dirname "$META")" && pwd)/$(basename "$META")"
H="$META/.claude/session-lessons"

# Sources the installed helpers (their paths derive from where they live).
use_installed() {
  [[ -f "$H/src/lib.sh" && -f "$H/state/install.json" ]] || die "nothing installed in $META. Run: $SELF install"
  source "$H/src/lib.sh"
}
refuse_if_running() {
  if [[ -f "$H/state/run.lock" ]] && lock_is_live "$H/state/run.lock"; then
    die "a run is in progress (state/run.lock). Try again when it ends."
  fi
}
confirm() {
  (( YES )) && return 0
  [[ -t 0 ]] || die "not confirmed (no terminal). Re-run with --yes."
  read -r -p "Proceed? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || { echo "Nothing changed."; exit 0; }
}
fmt_time() { date -d "@$1" '+%Y-%m-%d %H:%M'; }
cron_marker() { echo "# session-lessons:$META"; }

# ------------------------------------------------------------------------------
cmd_install() {
  local claude git_ok
  claude="$(command -v claude || true)"; [[ -n "$claude" ]] || die "claude is not on PATH. Install Claude Code first."
  command -v git >/dev/null 2>&1 || die "git is not on PATH."
  # The member's own helpers, pointed at the target meta repo.
  source "$MEMBER/src/lib.sh"
  SL_META="$META"; SL_HOME="$H"; SL_STATE="$H/state"; SL_CONFIG="$H/config.json"; SL_INSTALL="$H/state/install.json"
  refuse_if_running

  local scripts="$META/.claude/scripts" changes=() keep=() legacy_files=() legacy_dirs=() cron_old=() f
  local new_meta=0 new_git=0 env_file="$HOME/.claude/claude-scheduler.env" env_old=0 carry="{}"
  [[ -d "$META" ]] || new_meta=1
  [[ -d "$META/.git" ]] || new_git=1
  (( new_meta )) && changes+=("Create the meta repo folder.")
  (( new_git )) && changes+=("Run git init in the meta repo.")

  # The previous version of this tool, only where it points at this meta repo.
  for f in daily-digest-prepare.ps1 daily-digest-prepare.sh daily-digest-trigger.ps1 daily-digest-trigger.sh \
           weekly-lessons-prepare.ps1 weekly-lessons-prepare.sh weekly-lessons-trigger.ps1 weekly-lessons-trigger.sh \
           daily-summary.md daily-lessons.md weekly-lessons.md git-sync.ps1 git-sync.sh VERSION scheduler-config.json; do
    [[ -f "$scripts/$f" ]] && legacy_files+=("$scripts/$f")
  done
  for f in "$META"/.claude/skills/session-digest-* "$META/.claude/scheduled-session-digests"; do
    [[ -e "$f" ]] && legacy_dirs+=("$f")
  done
  mapfile -t cron_old < <(crontab -l 2>/dev/null | grep -F "$META/.claude/scripts/" | grep -E 'daily-digest-trigger\.sh|weekly-lessons-trigger\.sh' || true)
  [[ -f "$env_file" ]] && grep -qF "$META" "$env_file" && env_old=1
  (( ${#legacy_files[@]} )) && changes+=("Remove ${#legacy_files[@]} old script file(s) from .claude/scripts/ (other files stay).")
  (( ${#legacy_dirs[@]} )) && changes+=("Remove the old interactive skills and staging folder.")
  (( ${#cron_old[@]} )) && changes+=("Remove ${#cron_old[@]} old cron line(s).")
  (( env_old )) && changes+=("Remove ~/.claude/claude-scheduler.env.")
  [[ -f "$META/.claude/daily-lessons-cursor" ]] && changes+=("Carry the old daily-lessons progress marker over.")
  [[ -f "$META/.claude/weekly-lessons-cursor" ]] && changes+=("Carry the old weekly-lessons progress marker over.")
  if [[ -f "$scripts/scheduler-config.json" && ! -f "$H/config.json" ]]; then
    carry="$(jq -c '{schedule: ({dailyAt: .dailyLessons.scheduleTime, weeklyAt: .weeklyLessons.scheduleTime,
                       weeklyDay: .weeklyLessons.scheduleDayOfWeek} | with_entries(select(.value != null))),
                     thresholds: ({minUserTurns: .dailyLessons.minUserTurns,
                       minTranscriptChars: .dailyLessons.minTranscriptChars} | with_entries(select(.value != null)))}' \
             "$scripts/scheduler-config.json")"
    changes+=("Carry the old schedule and thresholds over.")
  fi
  [[ -f "$META/.claude/daily-summary-cursor" ]] && keep+=(".claude/daily-summary-cursor")
  [[ -d "$META/daily-summaries" ]] && keep+=("daily-summaries/")
  [[ -f "$META/.claude/settings.json" ]] && keep+=(".claude/settings.json")
  [[ -n "${C4_CLAUDE_META_DIR:-}" ]] && keep+=("the C4_CLAUDE_META_DIR variable")

  changes+=("Install the scripts into .claude/session-lessons/src/.")
  if [[ -f "$H/config.json" ]]; then changes+=("Keep config.json (add any missing extraction).")
  else changes+=("Create .claude/session-lessons/config.json."); fi
  local gi_new=() l
  for l in 'logs/*session-lessons-*' '.claude/session-lessons/state/' '.claude/session-lessons/staging/'; do
    grep -qxF "$l" "$META/.gitignore" 2>/dev/null || gi_new+=("$l")
  done
  (( ${#gi_new[@]} )) && changes+=("Add ${#gi_new[@]} line(s) to .gitignore.")
  local cron_line=""
  if (( ! NOSCHED )); then
    if crontab -l 2>/dev/null | grep -qF "$(cron_marker)"; then changes+=("Keep the existing hourly cron entry.")
    else
      cron_line="0 * * * * PATH='$PATH' bash '$H/src/run.sh' --scheduled $(cron_marker)"
      changes+=("Add an hourly cron entry (runs only what is due).")
    fi
  fi
  local roots=() count=0 r
  if [[ -n "${C4_CLAUDE_DIR:-}" ]]; then IFS=: read -r -a roots <<<"$C4_CLAUDE_DIR"
  else roots=("$HOME/.claude" "$HOME/.claude_devcontainer"); fi
  if (( ! NOARCH )); then
    for r in "${roots[@]}"; do
      [[ -d "$r/projects" ]] && count=$(( count + $(find "$r/projects" -name '*.jsonl' -not -path '*/subagents/*' | wc -l) ))
    done
    changes+=("Archive up to $count session(s) on disk (no claude cost).")
  fi

  echo "Install session lessons into:"
  echo "  $META"
  for f in "${changes[@]}"; do echo "  - $f"; done
  if (( ${#keep[@]} )); then echo "Left as they are:"; for f in "${keep[@]}"; do echo "  - $f"; done; fi
  confirm

  # --- apply ---
  mkdir -p "$META"
  (( new_git )) && git -C "$META" init -q
  mkdir -p "$H/state"
  local removed=()
  if [[ -f "$META/.claude/daily-lessons-cursor" ]]; then
    [[ -f "$H/state/daily.cursor" ]] || cp "$META/.claude/daily-lessons-cursor" "$H/state/daily.cursor"
    rm -f "$META/.claude/daily-lessons-cursor"; removed+=(".claude/daily-lessons-cursor")
  fi
  if [[ -f "$META/.claude/weekly-lessons-cursor" ]]; then
    [[ -f "$H/state/weekly-lessons.cursor" ]] || cp "$META/.claude/weekly-lessons-cursor" "$H/state/weekly-lessons.cursor"
    rm -f "$META/.claude/weekly-lessons-cursor"; removed+=(".claude/weekly-lessons-cursor")
  fi
  for f in "${legacy_files[@]}" "${legacy_dirs[@]}"; do rm -rf "$f"; removed+=("${f#"$META/"}"); done
  if (( ${#cron_old[@]} )); then
    local tab; tab="$(crontab -l 2>/dev/null || true)"
    for l in "${cron_old[@]}"; do tab="$(grep -vxF "$l" <<<"$tab" || true)"; removed+=("cron: $l"); done
    printf '%s\n' "$tab" | crontab -
  fi
  (( env_old )) && { rm -f "$env_file"; removed+=("$env_file"); }

  rm -rf "$H/src"; mkdir -p "$H/src"; cp -R "$MEMBER/src/." "$H/src/"

  local defaults; defaults="$(cat "$MEMBER/src/config.default.json")"
  local flags; flags="$(jq -nc --arg d "$DAILY_AT" --arg wd "$WEEKLY_DAY" --arg wa "$WEEKLY_AT" \
    '{schedule: ({dailyAt: $d, weeklyDay: $wd, weeklyAt: $wa} | with_entries(select(.value != "")))}')"
  if [[ -f "$H/config.json" ]]; then
    jq --argjson d "$defaults" --argjson f "$flags" \
      '.extractions = ($d.extractions + (.extractions // {})) | .schedule = ((.schedule // {}) + $f.schedule)' \
      "$H/config.json" > "$H/config.json.tmp"
  else
    jq -n --argjson d "$defaults" --argjson c "$carry" --argjson f "$flags" \
      '$d | .schedule += ($c.schedule // {}) | .thresholds += ($c.thresholds // {}) | .schedule += $f.schedule' \
      > "$H/config.json.tmp"
  fi
  mv "$H/config.json.tmp" "$H/config.json"

  local old="{}"; [[ -f "$H/state/install.json" ]] && old="$(cat "$H/state/install.json")"
  local added_cron=(); [[ -n "$cron_line" ]] && added_cron=("$cron_line")
  jq -n --argjson old "$old" --arg version "$(cat "$MEMBER/VERSION" 2>/dev/null || echo dev)" \
    --argjson now "$(date +%s)" --arg claude "$claude" --arg marker "$(cron_marker)" \
    --argjson roots "$(printf '%s\n' "${roots[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')" \
    --argjson newMeta "$([[ $new_meta == 1 ]] && echo true || echo false)" \
    --argjson newGit "$([[ $new_git == 1 ]] && echo true || echo false)" \
    --argjson cron "$(printf '%s\n' "${added_cron[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')" \
    --argjson gi "$(printf '%s\n' "${gi_new[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')" \
    --argjson removed "$(printf '%s\n' "${removed[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')" \
    '{version: $version, installedAt: ($old.installedAt // $now), claudePath: $claude,
      claudeNoToolsArgs: ["--tools", "", "--no-session-persistence"], scanRoots: $roots,
      taskName: $marker,
      installed: {
        createdMetaDir: ($old.installed.createdMetaDir // $newMeta),
        gitInit: ($old.installed.gitInit // $newGit),
        tasks: [],
        cronLines: ((($old.installed.cronLines // []) + $cron) | unique),
        gitignoreLines: ((($old.installed.gitignoreLines // []) + $gi) | unique),
        legacyRemoved: (($old.installed.legacyRemoved // []) + $removed)}}' > "$H/state/install.json.tmp"
  mv "$H/state/install.json.tmp" "$H/state/install.json"

  (( ${#gi_new[@]} )) && printf '%s\n' "${gi_new[@]}" >> "$META/.gitignore"
  if [[ -n "$cron_line" ]]; then
    { crontab -l 2>/dev/null || true; echo "$cron_line"; } | crontab -
  fi
  (( NOARCH )) || bash "$H/src/run.sh" --archive-only --all

  source "$H/src/lib.sh"
  echo "Installed."
  if (( NOSCHED )); then echo "Scheduled runs are off (--no-schedule)."
  else echo "First scheduled run: $(fmt_time "$(next_scheduled daily "$(date +%s)")")."; fi
  echo "For a first look, in the clone folder:"
  echo "  bash lessons.sh run --dry-run --meta-dir '$META'"
}

# ------------------------------------------------------------------------------
cmd_run() {
  use_installed
  bash "$H/src/run.sh" "${PASS[@]}"
}

# ------------------------------------------------------------------------------
cmd_status() {
  use_installed
  local now; now="$(date +%s)"
  echo "Session lessons in:"
  echo "  $META"
  echo "Schedule: daily at $(cfg '.schedule.dailyAt'), weekly on $(cfg '.schedule.weeklyDay') at $(cfg '.schedule.weeklyAt')."
  if crontab -l 2>/dev/null | grep -qF "$(cron_marker)"; then echo "Scheduled entry: registered (hourly)."
  else echo "Scheduled entry: not registered."; fi
  local j
  for j in daily weekly; do
    if job_due "$j"; then echo "Next $j run: due now."
    else echo "Next $j run: $(fmt_time "$(next_scheduled "$j" "$now")")."; fi
  done
  local c
  for c in "$H/state/daily.cursor" "$H"/state/weekly-*.cursor; do
    [[ -f "$c" ]] || continue
    echo "$(basename "$c" .cursor) progress: up to $(fmt_time "$(tr -d '[:space:]' < "$c")")."
  done
  for j in daily weekly; do
    local lr="$H/state/last-run-$j.json"
    if [[ -f "$lr" ]]; then
      echo "Last $j run: $(fmt_time "$(jq -r .finishedAt "$lr")"), $(jq -r .processed "$lr") processed, $(jq -r .failed "$lr") failed."
      [[ "$(jq -r '.error // empty' "$lr")" == "" ]] || echo "  Error: $(jq -r .error "$lr" | cut -c1-70)"
    else echo "Last $j run: none yet."; fi
  done
  local g="$H/state/given-up.txt"
  if [[ -s "$g" ]]; then
    echo "Given up ($(wc -l < "$g" | tr -d ' ')), retried after removing the line from state/given-up.txt:"
    while IFS= read -r l; do echo "  ${l:0:76}"; done < "$g"
  else echo "Given up: none."; fi
}

# ------------------------------------------------------------------------------
cmd_uninstall() {
  [[ -f "$H/state/install.json" ]] || { echo "Nothing installed in $META."; exit 0; }
  use_installed
  refuse_if_running
  local items=() l
  mapfile -t CRON < <(jq -r '.installed.cronLines[]?' "$H/state/install.json")
  mapfile -t GI < <(jq -r '.installed.gitignoreLines[]?' "$H/state/install.json")
  (( ${#CRON[@]} )) && items+=("Remove the hourly cron entry.")
  (( ${#GI[@]} )) && items+=("Remove the ${#GI[@]} .gitignore line(s) install added.")
  items+=("Remove .claude/session-lessons/src/, state/, and staging/.")
  local purge_paths=() e
  if (( PURGE )); then
    while IFS= read -r e; do purge_paths+=("$e"); done < <(cfg '.extractions[] | .outputDir, (.weekly.master // empty)')
    purge_paths+=("transcripts" ".claude/session-lessons")
    for e in "${purge_paths[@]}"; do items+=("Delete $e (purge)."); done
    items+=("Delete this tool's logs (logs/**/*session-lessons-*) (purge).")
  else
    items+=("Keep config.json, every output, transcripts/, and the logs.")
  fi
  echo "Uninstall session lessons from:"
  echo "  $META"
  for l in "${items[@]}"; do echo "  - $l"; done
  echo "The meta repo, its .git, and anything else in it stay."
  confirm

  if (( ${#CRON[@]} )); then
    local tab; tab="$(crontab -l 2>/dev/null || true)"
    for l in "${CRON[@]}"; do tab="$(grep -vxF "$l" <<<"$tab" || true)"; done
    printf '%s\n' "$tab" | crontab -
  fi
  if (( ${#GI[@]} )) && [[ -f "$META/.gitignore" ]]; then
    local tmp; tmp="$(mktemp)"
    grep -vxF -f <(printf '%s\n' "${GI[@]}") "$META/.gitignore" > "$tmp" || true
    mv "$tmp" "$META/.gitignore"
  fi
  rm -rf "$H/src" "$H/state" "$H/staging"
  if (( PURGE )); then
    for e in "${purge_paths[@]}"; do rm -rf "${META:?}/$e"; done
    [[ -d "$META/logs" ]] && find "$META/logs" -type f -name '*session-lessons-*' -delete
  fi
  echo "Uninstalled."
}

case "$CMD" in
  install) cmd_install ;;
  run) cmd_run ;;
  status) cmd_status ;;
  uninstall) cmd_uninstall ;;
  *) echo "Usage: $SELF install|run|status|uninstall [options]"; echo "See README.md for the options."; exit 1 ;;
esac
