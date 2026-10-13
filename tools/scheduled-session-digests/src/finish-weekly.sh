#!/usr/bin/env bash
# finish-weekly.sh: the weekly half of finish.
#
#   --ext <name> --batch <k>   merge batch k's answer into the master. Exits 0
#                              when the batch is done (merged, nothing new, or
#                              given up), 3 when it is not (run stops there).
#   --close --started <epoch> --trigger <t> --error <text> [--questions-warning <text>]
#                              advance each weekly cursor over its done batches,
#                              open new questions and end each replace master
#                              with the fixed When-to-ask section, write
#                              last-run-weekly.json, git-sync, clean up.
#
# Cross-reference: src/finish-weekly.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXT=""; BATCH=""; CLOSE=0; STARTED=""; TRIGGER=manual; ERROR=""; QWARN=""
while (( $# )); do
  case "$1" in
    --questions-warning) QWARN="$2"; shift 2 ;;
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
  answer="$SL_META/$("${JQ[@]}" -r .pending <<<"$b")"
  if [[ "$("${JQ[@]}" -r '.mode // "append"' "$MANIFEST")" == replace ]]; then
    # Replace: the answer's soul part, cut at "## When to ask", is the new master
    # when it starts "# SOUL", has "## Priorities" and "## Rules" lines, and fits
    # weekly.maxLines. A questions part with a "### " line is kept as
    # <outputDir>/questions/<runDate>_<batch cursorEpoch>.md; a missing or
    # malformed one is no questions.
    parts="$("${JQ[@]}" -Rs --argjson names '["soul","questions"]' -f "$SL_SRC/split.jq" "$answer")"
    soul="$(mktemp)"; qpart="$(mktemp)"; trap 'rm -f "$soul" "$qpart"' EXIT
    "${JQ[@]}" -j '.soul // ""' <<<"$parts" > "$soul"
    "${JQ[@]}" -j '.questions // ""' <<<"$parts" > "$qpart"
    body="$(soul_body "$soul")"; first="${body%%$'\n'*}"
    if [[ -n "$body" && ( "$first" == "# SOUL" || "$first" == "# SOUL "* ) ]] \
       && grep -qx '## Priorities' <<<"$body" && grep -qx '## Rules' <<<"$body" \
       && (( $(printf '%s\n' "$body" | wc -l) <= $(cfg ".extractions[\"$EXT\"].weekly.maxLines") )); then
      added=0; [[ "$body" == "$(soul_body "$master")" ]] || added=1
      mkdir -p "$(dirname "$master")"; printf '%s\n' "$body" > "$master"
      if grep -q '^### ' "$qpart"; then
        qd="$SL_META/$(cfg ".extractions[\"$EXT\"].outputDir")/questions"; mkdir -p "$qd"
        cp "$qpart" "$qd/$("${JQ[@]}" -r .runDate "$MANIFEST")_$("${JQ[@]}" -r .cursorEpoch <<<"$b").md"
      fi
      set_batch "$MANIFEST" "$BATCH" ".done = true | .added = $added"
      say "Batch $((BATCH + 1)): $(basename "$master") $( (( added )) && echo updated || echo unchanged)."
      exit 0
    fi
  else
    mfile="$master"; [[ -f "$mfile" ]] || { mfile="$(mktemp)"; trap 'rm -f "$mfile"' EXIT; }
    r="$("${JQ[@]}" -n --rawfile answer "$answer" --rawfile master "$mfile" \
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
  if [[ "$("${JQ[@]}" -r '.mode // "append"' "$m")" == replace ]]; then
    say "Weekly $ext: $w update(s), $p batch(es) answered, $f failed, $g given up."
    # New questions go out, then the fixed When-to-ask section replaces whatever
    # the master ends with: its issue bullet only when open found a private repo.
    qrepo=""
    if [[ "$(cfg ".extractions[\"$ext\"].weekly.questions.enabled // false")" == true ]]; then
      { IFS= read -r qrepo; IFS= read -r qw; } < <(bash "$SL_SRC/questions.sh" open --ext "$ext" --log "$SL_LOG")
      [[ -z "$qw" ]] || QWARN+="${QWARN:+; }$qw"
    fi
    mp="$SL_META/$("${JQ[@]}" -r .master "$m")"
    if [[ -f "$mp" ]]; then
      body="$(soul_body "$mp")"
      { [[ -z "$body" ]] || printf '%s\n\n' "$body"
        ask_section "$qrepo" "$(cfg ".extractions[\"$ext\"].weekly.questions.label // empty")"; } > "$mp"
    fi
  else
    say "Weekly $ext: $w lesson(s) added, $p batch(es) answered, $f failed, $g given up."
  fi
  results="$("${JQ[@]}" -c --arg e "$ext" --argjson w "$w" --argjson n "$nn" '.[$e] = {written: $w, none: $n}' <<<"$results")"
done
[[ -z "$ERROR" ]] || say "Error: $ERROR"

read -r committed pushed sync_error < <(bash "$SL_SRC/git-sync.sh" weekly "$SL_LOG")
if [[ -z "$ERROR" && -n "$sync_error" ]]; then ERROR="$sync_error"; say "Error: $ERROR"; fi

"${JQ[@]}" -n --argjson started "$STARTED" --argjson finished "$(now_epoch)" --arg trigger "$TRIGGER" \
  --argjson processed "$processed" --argjson results "$results" --argjson failed "$failed" \
  --argjson given "$given" --argjson committed "$committed" --argjson pushed "$pushed" --arg error "$ERROR" \
  --arg qwarn "$QWARN" \
  '{job: "weekly", startedAt: $started, finishedAt: $finished, trigger: $trigger,
    processed: $processed, results: $results, failed: $failed, givenUp: $given,
    deferred: 0, committed: $committed, pushed: $pushed,
    error: (if $error == "" then null else $error end),
    questionsWarning: (if $qwarn == "" then null else $qwarn end)}' > "$SL_STATE/last-run-weekly.json"

rm -rf "$SL_STAGING"/weekly-*; rmdir "$SL_STAGING" 2>/dev/null || true
[[ -z "$ERROR" ]] || exit 1
