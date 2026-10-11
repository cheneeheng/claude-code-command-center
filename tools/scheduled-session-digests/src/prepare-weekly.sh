#!/usr/bin/env bash
# prepare-weekly.sh: stages the weekly merge for one extraction. Collects the
# per-session files written since the cursor, skips no-content stubs and given-up
# files, and splits them into batches, each with the master's existing titles.
#
# Usage: prepare-weekly.sh --ext <name> --cutoff <epoch> --mode dry|stage
#                          [--write-cursor 0|1] [--log <file>]
# Writes staging/weekly-<ext>/manifest.json in stage mode.
#
# Cross-reference: src/prepare-weekly.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXT=""; CUTOFF=""; MODE=""; WRITE_CURSOR=0
while (( $# )); do
  case "$1" in
    --ext) EXT="$2"; shift 2 ;;
    --cutoff) CUTOFF="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --write-cursor) WRITE_CURSOR="$2"; shift 2 ;;
    --log) SL_LOG="$2"; shift 2 ;;
    *) echo "prepare-weekly: unknown argument $1" >&2; exit 1 ;;
  esac
done

OUT="$(cfg ".extractions[\"$EXT\"].outputDir")"
MASTER="$(cfg ".extractions[\"$EXT\"].weekly.master")"
LIMIT="$(cfg '.weeklyBatchChars')"
DIR="$SL_STAGING/weekly-$EXT"
RUN_DATE="$(date +%Y-%m-%d)"
GIVEN_UP="$SL_STATE/given-up.txt"

# Candidates: "<mtime> <meta-relative path>", by mtime, then path (bytewise).
declare -A GONE=()
if [[ -f "$GIVEN_UP" ]]; then while IFS= read -r k; do [[ -n "$k" ]] && GONE["$k"]=1; done < "$GIVEN_UP"; fi
mapfile -t CANDS < <(
  [[ -d "$SL_META/$OUT" ]] || exit 0
  cd "$SL_META"
  find "$OUT" -type f -name '*.md' -print0 | while IFS= read -r -d '' f; do
    m="$(mtime_epoch "$f")"; (( m > CUTOFF )) && printf '%s %s\n' "$m" "$f"
  done | LC_ALL=C sort -k1,1n -k2,2
)

newest="$CUTOFF"; FILES=()
for c in "${CANDS[@]}"; do
  m="${c%% *}"; f="${c#* }"; newest="$m"
  [[ -n "${GONE[weekly-$EXT:$f]:-}" ]] && continue
  [[ "$EXT" == lessons ]] && grep -qF "$LESSONS_STUB" "$SL_META/$f" && continue
  FILES+=("$m $f")
done

# The master's titles, grouped under their headings.
titles="(none yet)"
if [[ -f "$SL_META/$MASTER" ]]; then
  t="$(grep -E '^(## |### )' "$SL_META/$MASTER" || true)"
  [[ -n "$t" ]] && titles="$t"
fi

# One file's section of the input: "## Source: <file name>", a blank line, and
# the file's text without trailing newlines. Its size counts toward the batch.
section() { printf '## Source: %s\n\n%s' "$(basename "$1")" "$(cat "$SL_META/$1")"; }

# Batches: at most LIMIT code points of sections each; a same-mtime group is
# never split, and a group larger than the limit is a batch on its own.
if [[ "$MODE" == stage ]]; then rm -rf "$DIR"; mkdir -p "$DIR/in" "$DIR/out"; fi
batches="[]"; cur=(); cur_chars=0; total_tokens=0
flush() {
  (( ${#cur[@]} )) || return 0
  local k; k="$("${JQ[@]}" 'length' <<<"$batches")"
  local body="Run date: $RUN_DATE"$'\n\n'"# Existing titles"$'\n\n'"$titles"$'\n\n'"# New session files"$'\n'
  local files=() last=0 e
  for e in "${cur[@]}"; do
    last="${e%% *}"; f="${e#* }"; files+=("$f")
    body+=$'\n'"$(section "$f")"$'\n'
  done
  total_tokens=$(( total_tokens + $(printf '%s' "$body" | "${JQ[@]}" -Rs 'length') / 4 ))
  [[ "$MODE" == stage ]] && printf '%s' "$body" > "$DIR/in/batch-$k.md"
  batches="$("${JQ[@]}" -c --argjson c "$last" --arg k "$k" \
    --argjson files "$(printf '%s\n' "${files[@]}" | "${JQ[@]}" -Rsc 'split("\n") | map(select(. != ""))')" \
    --arg ext "$EXT" \
    '. + [{cursorEpoch: $c, files: $files,
           input: ".claude/session-lessons/staging/weekly-\($ext)/in/batch-\($k).md",
           pending: ".claude/session-lessons/staging/weekly-\($ext)/out/batch-\($k).md",
           exit: null}]' <<<"$batches")"
  cur=(); cur_chars=0
}
i=0
while (( i < ${#FILES[@]} )); do
  m="${FILES[$i]%% *}"; j=$i; group=(); gchars=0
  while (( j < ${#FILES[@]} )) && [[ "${FILES[$j]%% *}" == "$m" ]]; do
    f="${FILES[$j]#* }"; group+=("${FILES[$j]}")
    gchars=$(( gchars + $(section "$f" | "${JQ[@]}" -Rs 'length') ))
    j=$((j + 1))
  done
  if (( ${#cur[@]} > 0 && cur_chars + gchars > LIMIT )); then flush; fi
  cur+=("${group[@]}"); cur_chars=$(( cur_chars + gchars ))
  i=$j
done
flush

n="$("${JQ[@]}" 'length' <<<"$batches")"
SINCE="the beginning"; (( CUTOFF > 0 )) && SINCE="$(local_date "$CUTOFF")"
say "Weekly run ($EXT): ${#FILES[@]} file(s) in $n batch(es), since $SINCE."
say "About $total_tokens tokens (rough)."

if [[ "$MODE" == stage ]]; then
  "${JQ[@]}" -n --arg ext "$EXT" --argjson cutoff "$CUTOFF" --argjson newest "$newest" \
    --argjson write "$([[ "$WRITE_CURSOR" == 1 ]] && echo true || echo false)" \
    --arg since "$SINCE" --arg master "$MASTER" --arg date "$RUN_DATE" --argjson batches "$batches" \
    '{job: "weekly", extraction: $ext, cursorFile: ".claude/session-lessons/state/weekly-\($ext).cursor",
      cutoffEpoch: $cutoff, cursorEpoch: $newest, writeCursor: $write, since: $since,
      master: $master, runDate: $date, batches: $batches}' > "$DIR/manifest.json"
fi
