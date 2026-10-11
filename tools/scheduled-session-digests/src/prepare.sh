#!/usr/bin/env bash
# prepare.sh: scans Claude Code sessions, cleans each transcript, archives it
# under transcripts/, and stages the sessions that still need an extraction.
# Single owner of scanning, filtering, cleanup, archiving, and staging.
#
# Usage: prepare.sh --cutoff <epoch> --mode archive|dry|stage
#                   [--cap <n>] [--write-cursor 0|1]
#   archive  archive only (no staging, no cursor)
#   dry      print the preview, write nothing
#   stage    archive, then stage jobs and write staging/daily/manifest.json
#
# Cross-reference: src/prepare.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CUTOFF=""; MODE=""; CAP=0; WRITE_CURSOR=0
while (( $# )); do
  case "$1" in
    --cutoff) CUTOFF="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --write-cursor) WRITE_CURSOR="$2"; shift 2 ;;
    --log) SL_LOG="$2"; shift 2 ;;
    *) echo "prepare: unknown argument $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CUTOFF" && "$MODE" =~ ^(archive|dry|stage)$ ]] || { echo "prepare: --cutoff and --mode are required" >&2; exit 1; }

MIN_TURNS="$(cfg '.thresholds.minUserTurns')"
MIN_CHARS="$(cfg '.thresholds.minTranscriptChars')"
UPPER=$(( $(now_epoch) - $(cfg '.settleMinutes') * 60 ))
META_PROJECT="$(encode_project_dir "$SL_META")"
GIVEN_UP="$SL_STATE/given-up.txt"
DIR="$SL_STAGING/daily"

# --- scan (rules 1-3) ----------------------------------------------------------
# Lines of "<mtime> <uuid> <path>", sorted by mtime, then file name (bytewise).
candidates() {
  local root dir f m
  while IFS= read -r root; do
    [[ -d "$root/projects" ]] || continue
    for dir in "$root/projects"/*/; do
      [[ -d "$dir" ]] || continue
      [[ "$(basename "$dir")" == "$META_PROJECT" ]] && continue
      while IFS= read -r -d '' f; do
        [[ "$f" == */subagents/* ]] && continue
        [[ "$(head -n 1 "$f" | "${JQ[@]}" -r '.isSidechain // false' 2>/dev/null)" == "true" ]] && continue
        m="$(mtime_epoch "$f")"
        (( m > CUTOFF && m <= UPPER )) || continue
        printf '%s %s %s\n' "$m" "$(basename "$f" .jsonl)" "$f"
      done < <(find "$dir" -type f -name '*.jsonl' -print0)
    done
  done < <(inst_get '.scanRoots[]') | LC_ALL=C sort -k1,1n -k2,2
}

# --- what each session still needs (rule 4) ----------------------------------
# An extraction is done for a session when its outputDir holds a file named
# <date>_<uuid>[_<title>].md, or "<extraction>:<uuid>" is in given-up.txt.
declare -A DONE=()
EXTS=(); declare -A OUTDIR=()
while IFS=$'\t' read -r name out; do
  EXTS+=("$name"); OUTDIR[$name]="$out"
  if [[ -d "$SL_META/$out" ]]; then
    while IFS= read -r f; do
      f="${f%.md}"; f="${f#*_}"; DONE["$name:${f%%_*}"]=1
    done < <(find "$SL_META/$out" -type f -name '*.md' -printf '%f\n')
  fi
done < <(cfg '.extractions | to_entries[] | select(.value.enabled) | "\(.key)\t\(.value.outputDir)"')
if [[ -f "$GIVEN_UP" ]]; then
  while IFS= read -r k; do [[ -n "$k" ]] && DONE["$k"]=1; done < "$GIVEN_UP"
fi

[[ "$MODE" == stage ]] && { rm -rf "$DIR"; mkdir -p "$DIR/in" "$DIR/out"; }
JOBS="$(mktemp)"; trap 'rm -f "$JOBS"' EXIT

archived=0; skipped=0; newest="$CUTOFF"
while read -r mtime uuid path; do
  newest="$mtime"
  json="$("${JQ[@]}" -n -R -f "$SL_SRC/clean.jq" "$path")"
  read -r turns chars < <("${JQ[@]}" -r '"\(.turns) \(.body | length)"' <<<"$json")
  if (( turns < MIN_TURNS || chars < MIN_CHARS )); then skipped=$((skipped + 1)); continue; fi

  date="$(local_date "$mtime")"
  text="$("${JQ[@]}" -j --arg uuid "$uuid" --arg date "$date" \
    '"# Session Transcript\nUUID: \($uuid)\nDate: \($date)\nTitle: \(.title // $uuid)\nProject: \(.project)\nCleanup: v1\n\n## Conversation\n\n" + .body' \
    <<<"$json"; printf x)"; text="${text%x}"

  # Rule 7: archive every candidate that passes the thresholds.
  rel=""
  if [[ "$MODE" != dry ]]; then
    [[ -d "$SL_META/transcripts" ]] && rel="$(cd "$SL_META" && find transcripts -type f -name "*_${uuid}.md" | head -n 1)"
    [[ -n "$rel" ]] || rel="transcripts/${date:0:4}/${date:5:2}/${date}_${uuid}.md"
    mkdir -p "$SL_META/$(dirname "$rel")"
    printf '%s' "$text" > "$SL_META/$rel"
    archived=$((archived + 1))
  fi
  [[ "$MODE" == archive ]] && continue

  needed=()
  for e in "${EXTS[@]}"; do [[ -n "${DONE[$e:$uuid]:-}" ]] || needed+=("$e"); done
  if (( ${#needed[@]} == 0 )); then skipped=$((skipped + 1)); continue; fi

  title="$("${JQ[@]}" -r '.title // empty' <<<"$json")"
  suffix=""; [[ -n "$title" ]] && suffix="_$(safe_title "$title")"
  outs="{}"
  for e in "${needed[@]}"; do
    outs="$("${JQ[@]}" -c --arg e "$e" --arg p "${OUTDIR[$e]}/${date:0:4}/${date:5:2}/${date}_${uuid}${suffix}.md" '.[$e] = $p' <<<"$outs")"
  done
  ilen="$("${JQ[@]}" -Rs 'length' <<<"$text")"
  [[ "$MODE" == stage ]] && printf '%s' "$text" > "$DIR/in/$uuid.md"
  "${JQ[@]}" -nc --argjson mtime "$mtime" --arg uuid "$uuid" --arg date "$date" \
    --arg title "${title:-$uuid}" --argjson j "$json" --arg archive "$rel" \
    --argjson needed "$(printf '%s\n' "${needed[@]}" | "${JQ[@]}" -Rsc 'split("\n") | map(select(. != ""))')" \
    --argjson outputs "$outs" --argjson chars "$((ilen - 1))" \
    '{uuid: $uuid, date: $date, title: $title, project: $j.project, mtime: $mtime,
      input: ".claude/session-lessons/staging/daily/in/\($uuid).md", archive: $archive,
      pending: ".claude/session-lessons/staging/daily/out/\($uuid).md", exit: null,
      needed: $needed, outputs: $outputs, chars: $chars}' >> "$JOBS"
done < <(candidates)

if [[ "$MODE" == archive ]]; then
  echo "Archived $archived session(s), skipped $skipped (too short)."
  exit 0
fi

# The cap and the manifest. A group of sessions with the same mtime second is
# never split: staging stops before a group that would cross the cap, except
# that a first group larger than the cap is staged whole.
SINCE="the beginning"; (( CUTOFF > 0 )) && SINCE="$(local_date "$CUTOFF")"
MANIFEST="$("${JQ[@]}" -s \
  --argjson cap "$CAP" --argjson cutoff "$CUTOFF" --argjson newest "$newest" \
  --argjson write "$([[ "$WRITE_CURSOR" == 1 ]] && echo true || echo false)" \
  --argjson skipped "$skipped" --arg since "$SINCE" '
  . as $all
  | (if $cap > 0 and ($all | length) > $cap then
       reduce ($all | group_by(.mtime))[] as $g ({s: [], stop: false};
         if .stop then .
         elif (.s | length) == 0 or ((.s | length) + ($g | length)) <= $cap then .s += $g
         else .stop = true end) | .s
     else $all end) as $staged
  | {job: "daily", cursorFile: ".claude/session-lessons/state/daily.cursor",
     cutoffEpoch: $cutoff,
     cursorEpoch: (if ($staged | length) < ($all | length) then ($staged | last | .mtime) else $newest end),
     writeCursor: $write, since: $since, skipped: $skipped,
     deferred: (($all | length) - ($staged | length)),
     approxTokens: ([$staged[].chars] | add // 0 | . / 4 | floor),
     jobs: [$staged[] | del(.chars)]}' "$JOBS")"

n="$("${JQ[@]}" '.jobs | length' <<<"$MANIFEST")"
read -r deferred tokens < <("${JQ[@]}" -r '"\(.deferred) \(.approxTokens)"' <<<"$MANIFEST")
say "Daily run: $n session(s) to process, since $SINCE."
say "Skipped $skipped (too short or done), deferred $deferred, about $tokens tokens (rough)."

if [[ "$MODE" == stage ]]; then
  # Deferred sessions keep their archive but not their staged input.
  for f in "$DIR/in"/*.md; do
    [[ -e "$f" ]] || continue
    "${JQ[@]}" -e --arg u "$(basename "$f" .md)" 'any(.jobs[]; .uuid == $u)' <<<"$MANIFEST" >/dev/null || rm -f "$f"
  done
  printf '%s\n' "$MANIFEST" > "$DIR/manifest.json"
fi
