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
[[ "$JOB" == daily ]] || { echo "run: only --job daily is built so far" >&2; exit 1; }

acquire_lock
STARTED="$(now_epoch)"

# Cutoff: -All is 0, -Since is that local date's midnight, otherwise the stored
# cursor, or now - firstRunDays when there is none.
CURSOR_FILE="$SL_STATE/daily.cursor"
STORED=""; [[ -f "$CURSOR_FILE" ]] && STORED="$(tr -d '[:space:]' < "$CURSOR_FILE")"
if (( ALL )); then CUTOFF=0
elif [[ -n "$SINCE" ]]; then CUTOFF="$(date -d "$SINCE" +%s)"
elif [[ -n "$STORED" ]]; then CUTOFF="$STORED"
else CUTOFF=$(( $(now_epoch) - $(cfg '.firstRunDays') * 86400 ))
fi

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
  if [[ ! -t 0 ]]; then echo "Not confirmed (no terminal). Re-run with --yes to proceed."; exit 0; fi
  read -r -p "Proceed? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Nothing done."; exit 0; }
fi

# A real run with no cursor writes its own cutoff first, so a failing first run
# never lets the window slide. writeCursor: only when this run's cutoff is at
# or before the stored cursor, so no unscanned range is ever skipped.
if [[ -z "$STORED" ]]; then printf '%s\n' "$CUTOFF" > "$CURSOR_FILE"; STORED="$CUTOFF"; fi
WRITE=0; (( CUTOFF <= STORED )) && WRITE=1

mkdir -p "$SL_META/logs/$(date +%Y)/$(date +%m)"
SL_LOG="$SL_META/logs/$(date +%Y)/$(date +%m)/$(date +%Y%m%d_%H%M%S)_session-lessons-daily.log"
CAP=0; (( SCHEDULED )) && CAP="$(cfg '.maxSessionsPerRun')"

bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --mode stage --cap "$CAP" --write-cursor "$WRITE" --log "$SL_LOG"

MANIFEST="$SL_STAGING/daily/manifest.json"
CLAUDE="$(inst_get '.claudePath')"
mapfile -t NOTOOLS < <(inst_get '.claudeNoToolsArgs // [] | .[]')
MODEL="$(cfg '.models.daily.model')"; EFFORT="$(cfg '.models.daily.effort')"
ERROR=""

if [[ ! -e "$CLAUDE" ]] && ! command -v "$CLAUDE" >/dev/null 2>&1; then
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

TRIGGER=manual; (( SCHEDULED )) && TRIGGER=scheduled
bash "$SL_SRC/finish.sh" --started "$STARTED" --trigger "$TRIGGER" --error "$ERROR" --log "$SL_LOG"
[[ -z "$ERROR" ]] || exit 1
