#!/usr/bin/env bash
# finish.sh: single owner of splitting answers, validation, moving outputs into
# place, attempt counting, advancing the cursor, the last-run summary, git-sync,
# and staging cleanup. Called by run.sh after the claude calls.
#
# Usage: finish.sh --started <epoch> --trigger manual|scheduled --error <text>
#
# Cross-reference: src/finish.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STARTED=""; TRIGGER=manual; ERROR=""
while (( $# )); do
  case "$1" in
    --started) STARTED="$2"; shift 2 ;;
    --trigger) TRIGGER="$2"; shift 2 ;;
    --error) ERROR="$2"; shift 2 ;;
    --log) SL_LOG="$2"; shift 2 ;;
    *) echo "finish: unknown argument $1" >&2; exit 1 ;;
  esac
done

DIR="$SL_STAGING/daily"
MANIFEST="$DIR/manifest.json"
ATTEMPTS="$SL_STATE/attempts.json"
GIVEN_UP="$SL_STATE/given-up.txt"
MAX="$(cfg '.maxAttempts')"
[[ -f "$ATTEMPTS" ]] || echo '{}' > "$ATTEMPTS"

# A lessons part starts with "# Lessons — " and names the session. Any other
# extraction must be non-empty and contain the session UUID.
valid_part() {  # <extraction> <uuid> <file>
  local head; head="$(head -c 64 "$3")"
  case "$1" in
    lessons) [[ "$head" == "# Lessons "$'\xe2\x80\x94'" "* ]] && grep -qF "**Session**: $2" "$3" ;;
    *) [[ -s "$3" ]] && grep -qF "$2" "$3" ;;
  esac
}
is_none() {  # <extraction> <file>: the "nothing found" form (config .none) of a valid part
  local n; n="$(cfg ".extractions[\"$1\"].none // empty")"
  [[ -n "$n" ]] && grep -qF "$n" "$2"
}

processed=0; failed=0; given=0; oldest_undone=""
declare -A written=() none=()
while IFS=$'\t' read -r uuid mtime code; do
  if [[ "$code" != 0 ]]; then
    # Never called, or claude failed: nothing is moved or counted.
    [[ "$code" == null ]] || failed=$((failed + 1))
    [[ -n "$oldest_undone" ]] || oldest_undone="$mtime"
    continue
  fi
  processed=$((processed + 1))
  names="$("${JQ[@]}" -c --arg u "$uuid" '.jobs[] | select(.uuid == $u) | .needed' "$MANIFEST")"
  parts="$("${JQ[@]}" -Rs --argjson names "$names" -f "$SL_SRC/split.jq" "$DIR/out/$uuid.md")"
  done_all=1
  while IFS=$'\t' read -r e out; do
    part="$DIR/out/$uuid.$e.part"
    "${JQ[@]}" -j --arg e "$e" '.[$e] // ""' <<<"$parts" > "$part"
    if valid_part "$e" "$uuid" "$part"; then
      mkdir -p "$SL_META/$(dirname "$out")"
      mv "$part" "$SL_META/$out"
      if is_none "$e" "$SL_META/$out"; then none[$e]=$(( ${none[$e]:-0} + 1 ))
      else written[$e]=$(( ${written[$e]:-0} + 1 )); fi
    else
      n="$("${JQ[@]}" -r --arg k "$e:$uuid" '(.[$k] // 0) + 1' "$ATTEMPTS")"
      tmp="$(mktemp)"; "${JQ[@]}" --arg k "$e:$uuid" --argjson n "$n" '.[$k] = $n' "$ATTEMPTS" > "$tmp" && mv "$tmp" "$ATTEMPTS"
      if (( n >= MAX )); then
        echo "$e:$uuid" >> "$GIVEN_UP"; given=$((given + 1))
        say "Gave up on $e for ${uuid:0:8} after $n invalid answers."
      else
        done_all=0
      fi
    fi
  done < <("${JQ[@]}" -r --arg u "$uuid" '.jobs[] | select(.uuid == $u) | .outputs | to_entries[] | [.key, .value] | @tsv' "$MANIFEST")
  if (( ! done_all )); then
    failed=$((failed + 1))
    [[ -n "$oldest_undone" ]] || oldest_undone="$mtime"
  fi
done < <("${JQ[@]}" -r '.jobs[] | [.uuid, .mtime, (.exit | tostring)] | @tsv' "$MANIFEST")

# Advance the cursor to the smaller of cursorEpoch and (oldest undone - 1).
if [[ "$("${JQ[@]}" -r .writeCursor "$MANIFEST")" == true ]]; then
  cur="$("${JQ[@]}" -r .cursorEpoch "$MANIFEST")"
  [[ -n "$oldest_undone" ]] && (( oldest_undone - 1 < cur )) && cur=$(( oldest_undone - 1 ))
  printf '%s\n' "$cur" > "$SL_STATE/daily.cursor"
fi

deferred="$("${JQ[@]}" -r .deferred "$MANIFEST")"
say "Done: $processed processed, $failed failed (retried next run), $given given up, $deferred deferred."
results="{}"
while IFS= read -r e; do
  say "  $e: ${written[$e]:-0} written, ${none[$e]:-0} with nothing found."
  results="$("${JQ[@]}" -c --arg e "$e" --argjson w "${written[$e]:-0}" --argjson n "${none[$e]:-0}" '.[$e] = {written: $w, none: $n}' <<<"$results")"
done < <(cfg '.extractions | to_entries[] | select(.value.enabled) | .key')
[[ -z "$ERROR" ]] || say "Error: $ERROR"

read -r committed pushed sync_error < <(bash "$SL_SRC/git-sync.sh" daily "$SL_LOG")
if [[ -z "$ERROR" && -n "$sync_error" ]]; then ERROR="$sync_error"; say "Error: $ERROR"; fi

"${JQ[@]}" -n --argjson started "$STARTED" --argjson finished "$(now_epoch)" --arg trigger "$TRIGGER" \
  --argjson processed "$processed" --argjson results "$results" --argjson failed "$failed" \
  --argjson given "$given" --argjson deferred "$deferred" --argjson committed "$committed" \
  --argjson pushed "$pushed" --arg error "$ERROR" \
  '{job: "daily", startedAt: $started, finishedAt: $finished, trigger: $trigger,
    processed: $processed, results: $results, failed: $failed, givenUp: $given,
    deferred: $deferred, committed: $committed, pushed: $pushed,
    error: (if $error == "" then null else $error end)}' > "$SL_STATE/last-run-daily.json"

rm -rf "$DIR"; rmdir "$SL_STAGING" 2>/dev/null || true
[[ -z "$ERROR" ]] || exit 1
