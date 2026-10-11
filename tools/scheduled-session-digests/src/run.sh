#!/usr/bin/env bash
# run.sh: the only consumer of the pipeline. Takes the lock, works out the
# scan cutoff, calls prepare, sends each staged session to claude once, and
# hands the answers to finish.
#
# Usage: run.sh [--job daily] [--all | --since <yyyy-mm-dd>]
#               [--dry-run | --archive-only] [--yes] [--scheduled]
# The meta repo is the one this installed copy lives in.
#
# Cross-reference: src/run.ps1 is the PowerShell twin.

set -euo pipefail

ALL=0; SINCE=""; ARCHIVE_ONLY=0; DRY=0; YES=0; SCHEDULED=0; JOB=daily
while (( $# )); do
  case "$1" in
    --job) JOB="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --archive-only) ARCHIVE_ONLY=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --yes) YES=1; shift ;;
    --scheduled) SCHEDULED=1; YES=1; shift ;;
    *) echo "run: unknown argument $1" >&2; exit 1 ;;
  esac
done

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[[ "$JOB" =~ ^(daily|weekly)$ ]] || { echo "run: --job is daily or weekly" >&2; exit 1; }

acquire_lock
STARTED="$(now_epoch)"

# Cutoff: -All is 0, -Since is that local date's midnight, otherwise the stored
# cursor, or now - firstRunDays when there is none.
stored_cursor() { [[ -f "$1" ]] && tr -d '[:space:]' < "$1" || true; }
cutoff_for() {
  local stored="$1"
  if (( ALL )); then echo 0
  elif [[ -n "$SINCE" ]]; then date -d "$SINCE" +%s
  elif [[ -n "$stored" ]]; then echo "$stored"
  else echo $(( $(now_epoch) - $(cfg '.firstRunDays') * 86400 ))
  fi
}
confirm() {
  if [[ ! -t 0 ]]; then echo "Not confirmed (no terminal). Re-run with --yes to proceed."; exit 0; fi
  read -r -p "Proceed? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing done."; exit 0; }
}
open_log() {
  mkdir -p "$SL_META/logs/$(date +%Y)/$(date +%m)"
  SL_LOG="$SL_META/logs/$(date +%Y)/$(date +%m)/$(date +%Y%m%d_%H%M%S)_session-lessons-$1.log"
}
find_claude() {
  CLAUDE="$(inst_get '.claudePath')"
  mapfile -t NOTOOLS < <(inst_get '.claudeNoToolsArgs // [] | .[]')
  [[ -e "$CLAUDE" ]] || command -v "$CLAUDE" >/dev/null 2>&1
}
TRIGGER=manual; (( SCHEDULED )) && TRIGGER=scheduled

# --- weekly: one merge per extraction with a weekly entry ----------------------
if [[ "$JOB" == weekly ]]; then
  mapfile -t EXTS < <(cfg '.extractions | to_entries[] | select(.value.enabled and .value.weekly != null) | .key')
  declare -A CUT=() STO=()
  for e in "${EXTS[@]}"; do STO[$e]="$(stored_cursor "$SL_STATE/weekly-$e.cursor")"; CUT[$e]="$(cutoff_for "${STO[$e]}")"; done
  if (( DRY || ! YES )); then
    for e in "${EXTS[@]}"; do bash "$SL_SRC/prepare-weekly.sh" --ext "$e" --cutoff "${CUT[$e]}" --mode dry; done
    (( DRY )) && exit 0
    confirm
  fi
  open_log weekly
  for e in "${EXTS[@]}"; do
    [[ -n "${STO[$e]}" ]] || { printf '%s\n' "${CUT[$e]}" > "$SL_STATE/weekly-$e.cursor"; STO[$e]="${CUT[$e]}"; }
    W=0; (( CUT[$e] <= STO[$e] )) && W=1
    bash "$SL_SRC/prepare-weekly.sh" --ext "$e" --cutoff "${CUT[$e]}" --mode stage --write-cursor "$W" --log "$SL_LOG"
  done
  ERROR=""
  if ! find_claude; then
    ERROR="claude not found at $CLAUDE"
  else
    MODEL="$(cfg '.models.weekly.model')"; EFFORT="$(cfg '.models.weekly.effort')"
    cd "$SL_META"
    for e in "${EXTS[@]}"; do
      M="$SL_STAGING/weekly-$e/manifest.json"
      prompt="$(cat "$SL_SRC/prompts/$(cfg ".extractions[\"$e\"].weekly.prompt")")"
      n="$("${JQ[@]}" '.batches | length' "$M")"
      stop=0
      for (( k = 0; k < n; k++ )); do
        in="$SL_META/$("${JQ[@]}" -r --argjson k "$k" '.batches[$k].input' "$M")"
        out="$SL_META/$("${JQ[@]}" -r --argjson k "$k" '.batches[$k].pending' "$M")"
        set +e
        "$CLAUDE" --print --model "$MODEL" --effort "$EFFORT" "${NOTOOLS[@]}" "$prompt" < "$in" > "$out" 2> "$out.err"
        code=$?
        set -e
        [[ -s "$out.err" ]] && cat "$out.err" >> "$SL_LOG"
        tmp="$(mktemp)"; "${JQ[@]}" --argjson k "$k" --argjson x "$code" '.batches[$k].exit = $x' "$M" > "$tmp" && mv "$tmp" "$M"
        if (( code != 0 )); then
          say "Batch $((k + 1)): claude exited $code, stopping."
          ERROR="claude exited $code: $(grep -m 1 -v '^[[:space:]]*$' "$out.err" || true)"
          stop=1; break
        fi
        bash "$SL_SRC/finish-weekly.sh" --ext "$e" --batch "$k" --log "$SL_LOG" || { stop=1; break; }
      done
      (( stop )) && break
    done
  fi
  bash "$SL_SRC/finish-weekly.sh" --close --started "$STARTED" --trigger "$TRIGGER" --error "$ERROR" --log "$SL_LOG"
  [[ -z "$ERROR" ]] || exit 1
  exit 0
fi

# --- daily -----------------------------------------------------------------------
CURSOR_FILE="$SL_STATE/daily.cursor"
STORED="$(stored_cursor "$CURSOR_FILE")"
CUTOFF="$(cutoff_for "$STORED")"

if (( ARCHIVE_ONLY )); then
  bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --mode archive   # never touches a cursor
  exit 0
fi
if (( DRY )); then
  bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --mode dry       # writes nothing at all
  exit 0
fi
if (( ! YES )); then
  bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --mode dry
  confirm
fi

# A real run with no cursor writes its own cutoff first, so a failing first run
# never lets the window slide. writeCursor: only when this run's cutoff is at
# or before the stored cursor, so no unscanned range is ever skipped.
if [[ -z "$STORED" ]]; then printf '%s\n' "$CUTOFF" > "$CURSOR_FILE"; STORED="$CUTOFF"; fi
WRITE=0; (( CUTOFF <= STORED )) && WRITE=1

open_log daily
CAP=0; (( SCHEDULED )) && CAP="$(cfg '.maxSessionsPerRun')"

bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --mode stage --cap "$CAP" --write-cursor "$WRITE" --log "$SL_LOG"

MANIFEST="$SL_STAGING/daily/manifest.json"
MODEL="$(cfg '.models.daily.model')"; EFFORT="$(cfg '.models.daily.effort')"
ERROR=""

if ! find_claude; then
  ERROR="claude not found at $CLAUDE"
else
  FRAME="$(cat "$SL_SRC/prompts/daily-frame.md")"
  total="$("${JQ[@]}" '.jobs | length' "$MANIFEST")"
  i=0
  cd "$SL_META"
  while IFS=$'\t' read -r uuid date needed; do
    i=$((i + 1))
    parts=""; sections=""
    for e in ${needed//,/ }; do
      parts+="<<<extraction:$e>>>"$'\n'
      sections+=$'\n\n'"$(cat "$SL_SRC/prompts/$(cfg ".extractions[\"$e\"].prompt")")"
    done
    prompt="${FRAME/\{\{PARTS\}\}/${parts%$'\n'}}$sections"
    err="$SL_STAGING/daily/out/$uuid.err"
    set +e
    "$CLAUDE" --print --model "$MODEL" --effort "$EFFORT" "${NOTOOLS[@]}" "$prompt" \
      < "$SL_STAGING/daily/in/$uuid.md" > "$SL_STAGING/daily/out/$uuid.md" 2> "$err"
    code=$?
    set -e
    [[ -s "$err" ]] && cat "$err" >> "$SL_LOG"
    tmp="$(mktemp)"
    "${JQ[@]}" --arg u "$uuid" --argjson x "$code" '(.jobs[] | select(.uuid == $u) | .exit) = $x' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
    if (( code != 0 )); then
      say "[$i/$total] $date ${uuid:0:8}: claude exited $code, stopping."
      ERROR="claude exited $code: $(grep -m 1 -v '^[[:space:]]*$' "$err" || true)"
      break
    fi
    say "[$i/$total] $date ${uuid:0:8}: answered"
  done < <("${JQ[@]}" -r '.jobs[] | [.uuid, .date, (.needed | join(","))] | @tsv' "$MANIFEST")
fi

bash "$SL_SRC/finish.sh" --started "$STARTED" --trigger "$TRIGGER" --error "$ERROR" --log "$SL_LOG"
[[ -z "$ERROR" ]] || exit 1
