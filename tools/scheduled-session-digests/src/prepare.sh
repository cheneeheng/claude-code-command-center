#!/usr/bin/env bash
# prepare.sh: scans Claude Code sessions, cleans each transcript, and archives
# it under transcripts/. Single owner of scanning, filtering, cleanup, and
# archiving. Called by run.sh.
#
# Usage: prepare.sh --cutoff <epoch> [--archive-only]
#
# Cross-reference: src/prepare.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CUTOFF=""; ARCHIVE_ONLY=0
while (( $# )); do
  case "$1" in
    --cutoff) CUTOFF="$2"; shift 2 ;;
    --archive-only) ARCHIVE_ONLY=1; shift ;;
    *) echo "prepare: unknown argument $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CUTOFF" ]] || { echo "prepare: --cutoff is required" >&2; exit 1; }
(( ARCHIVE_ONLY )) || { echo "prepare: only --archive-only is built so far" >&2; exit 1; }

MIN_TURNS="$(cfg '.thresholds.minUserTurns')"
MIN_CHARS="$(cfg '.thresholds.minTranscriptChars')"
SETTLE=$(( $(cfg '.settleMinutes') * 60 ))
UPPER=$(( $(now_epoch) - SETTLE ))
META_PROJECT="$(encode_project_dir "$SL_META")"

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

# --- archive (rule 7) ----------------------------------------------------------
archived=0; skipped=0
while read -r mtime uuid path; do
  json="$("${JQ[@]}" -n -R -f "$SL_SRC/clean.jq" "$path")"
  read -r turns chars < <("${JQ[@]}" -r '"\(.turns) \(.body | length)"' <<<"$json")
  if (( turns < MIN_TURNS || chars < MIN_CHARS )); then
    skipped=$((skipped + 1)); continue
  fi
  date="$(local_date "$mtime")"
  dest=""
  [[ -d "$SL_META/transcripts" ]] && dest="$(find "$SL_META/transcripts" -type f -name "*_${uuid}.md" | head -n 1)"
  [[ -n "$dest" ]] || dest="$SL_META/transcripts/${date:0:4}/${date:5:2}/${date}_${uuid}.md"
  mkdir -p "$(dirname "$dest")"
  "${JQ[@]}" -j --arg uuid "$uuid" --arg date "$date" \
    '"# Session Transcript\nUUID: \($uuid)\nDate: \($date)\nTitle: \(.title // $uuid)\nProject: \(.project)\nCleanup: v1\n\n## Conversation\n\n" + .body' \
    <<<"$json" > "$dest"
  archived=$((archived + 1))
done < <(candidates)

echo "Archived $archived session(s), skipped $skipped (too short)."
