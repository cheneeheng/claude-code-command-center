#!/usr/bin/env bash
# finish-weekly.sh: the weekly half of finish.
#
#   --ext <name> --batch <k>   merge batch k's answer into the master. Exits 0
#                              when the batch is done (merged, nothing new, or
#                              given up), 3 when it is not (run stops there).
#   --close --started <epoch> --trigger <t> --error <text>
#                              advance each weekly cursor over its done batches,
#                              write last-run-weekly.json, git-sync, clean up.
#
# Cross-reference: src/finish-weekly.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXT=""; BATCH=""; CLOSE=0; STARTED=""; TRIGGER=manual; ERROR=""
while (( $# )); do
  case "$1" in
    --ext) EXT="$2"; shift 2 ;;
    --batch) BATCH="$2"; shift 2 ;;
    --close) CLOSE=1; shift ;;
    --started) STARTED="$2"; shift 2 ;;
    --trigger) TRIGGER="$2"; shift 2 ;;
    --error) ERROR="$2"; shift 2 ;;
    --log) SL_LOG="$2"; shift 2 ;;
    *) echo "finish-weekly: unknown argument $1" >&2; exit 1 ;;
  esac
done

ATTEMPTS="$SL_STATE/attempts.json"; GIVEN_UP="$SL_STATE/given-up.txt"
[[ -f "$ATTEMPTS" ]] || echo '{}' > "$ATTEMPTS"

set_batch() {  # <manifest> <k> <jq assignment>
  local tmp; tmp="$(mktemp)"
  "${JQ[@]}" --argjson k "$2" ".batches[\$k] |= ($3)" "$1" > "$tmp" && mv "$tmp" "$1"
}

if (( ! CLOSE )); then
  MANIFEST="$SL_STAGING/weekly-$EXT/manifest.json"
  b="$("${JQ[@]}" -c --argjson k "$BATCH" '.batches[$k]' "$MANIFEST")"
  [[ "$("${JQ[@]}" -r .exit <<<"$b")" == 0 ]] || exit 3
  master="$SL_META/$("${JQ[@]}" -r .master "$MANIFEST")"
  mfile="$master"; [[ -f "$mfile" ]] || { mfile="$(mktemp)"; trap 'rm -f "$mfile"' EXIT; }
  r="$("${JQ[@]}" -n --rawfile answer "$SL_META/$("${JQ[@]}" -r .pending <<<"$b")" --rawfile master "$mfile" \
       --arg date "$("${JQ[@]}" -r .runDate "$MANIFEST")" --argjson categories "$LESSONS_CATEGORIES" \
       -f "$SL_SRC/merge.jq")"
  status="$("${JQ[@]}" -r .status <<<"$r")"; added="$("${JQ[@]}" -r .added <<<"$r")"
  if [[ "$status" == merged ]]; then
    mkdir -p "$(dirname "$master")"
    "${JQ[@]}" -j .merged <<<"$r" > "$master"
  fi
  if [[ "$status" != invalid ]]; then
    set_batch "$MANIFEST" "$BATCH" ".done = true | .added = $added"
    say "Batch $((BATCH + 1)): $added lesson(s) added."
    exit 0
  fi
  key="weekly-$EXT:$("${JQ[@]}" -r '.files[0]' <<<"$b")"
  n="$("${JQ[@]}" -r --arg k "$key" '(.[$k] // 0) + 1' "$ATTEMPTS")"
  tmp="$(mktemp)"; "${JQ[@]}" --arg k "$key" --argjson n "$n" '.[$k] = $n' "$ATTEMPTS" > "$tmp" && mv "$tmp" "$ATTEMPTS"
  if (( n >= $(cfg '.maxAttempts') )); then
    "${JQ[@]}" -r --arg e "$EXT" '.files[] | "weekly-\($e):\(.)"' <<<"$b" >> "$GIVEN_UP"
    set_batch "$MANIFEST" "$BATCH" '.done = true | .givenUp = true | .added = 0'
    say "Gave up on weekly batch $((BATCH + 1)) after $n invalid answers."
    exit 0
  fi
  say "Batch $((BATCH + 1)): invalid answer, stopping (retried next run)."
  exit 3
fi

# --- close ---------------------------------------------------------------------
processed=0; failed=0; given=0; results="{}"
for m in "$SL_STAGING"/weekly-*/manifest.json; do
  [[ -e "$m" ]] || continue
  ext="$("${JQ[@]}" -r .extraction "$m")"
  read -r p f g w nn cur < <("${JQ[@]}" -r '
    [.batches[] | select(.exit == 0)] as $called
    | (.batches | map(.done == true) | index(false)) as $first_undone
    | [ ($called | length),
        ([.batches[] | select(.exit != null and .done != true)] | length),
        ([.batches[] | select(.givenUp == true)] | length),
        ([.batches[] | .added // 0] | add // 0),
        ([.batches[] | select(.done == true and .givenUp != true and (.added // 0) == 0)] | length),
        (if .writeCursor | not then "keep"
         elif $first_undone == null then .cursorEpoch
         elif $first_undone == 0 then "keep"
         else .batches[$first_undone - 1].cursorEpoch end)
      ] | map(tostring) | join(" ")' "$m")
  processed=$((processed + p)); failed=$((failed + f)); given=$((given + g))
  [[ "$cur" == keep ]] || printf '%s\n' "$cur" > "$SL_STATE/weekly-$ext.cursor"
  say "Weekly $ext: $w lesson(s) added, $p batch(es) answered, $f failed, $g given up."
  results="$("${JQ[@]}" -c --arg e "$ext" --argjson w "$w" --argjson n "$nn" '.[$e] = {written: $w, none: $n}' <<<"$results")"
done
[[ -z "$ERROR" ]] || say "Error: $ERROR"

read -r committed pushed < <(bash "$SL_SRC/git-sync.sh" weekly "$SL_LOG")

"${JQ[@]}" -n --argjson started "$STARTED" --argjson finished "$(now_epoch)" --arg trigger "$TRIGGER" \
  --argjson processed "$processed" --argjson results "$results" --argjson failed "$failed" \
  --argjson given "$given" --argjson committed "$committed" --argjson pushed "$pushed" --arg error "$ERROR" \
  '{job: "weekly", startedAt: $started, finishedAt: $finished, trigger: $trigger,
    processed: $processed, results: $results, failed: $failed, givenUp: $given,
    deferred: 0, committed: $committed, pushed: $pushed,
    error: (if $error == "" then null else $error end)}' > "$SL_STATE/last-run-weekly.json"

rm -rf "$SL_STAGING"/weekly-*; rmdir "$SL_STAGING" 2>/dev/null || true
