#!/usr/bin/env bash
# run.sh: the only consumer of the pipeline. Takes the lock, works out the
# scan cutoff, and drives prepare (and, from Phase 2, claude and finish).
#
# Usage: run.sh [--meta-dir <path>] [--all | --since <yyyy-mm-dd>] [--archive-only]
#
# Cross-reference: src/run.ps1 is the PowerShell twin.

set -euo pipefail

ALL=0; SINCE=""; ARCHIVE_ONLY=0
while (( $# )); do
  case "$1" in
    --meta-dir) export SL_META="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --archive-only) ARCHIVE_ONLY=1; shift ;;
    *) echo "run: unknown argument $1" >&2; exit 1 ;;
  esac
done

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
(( ARCHIVE_ONLY )) || { echo "run: only --archive-only is built so far" >&2; exit 1; }

acquire_lock

# Cutoff: -All is 0, -Since is that local date's midnight, otherwise the stored
# cursor, or now - firstRunDays when there is none. -ArchiveOnly never writes a
# cursor.
if (( ALL )); then
  CUTOFF=0
elif [[ -n "$SINCE" ]]; then
  CUTOFF="$(date -d "$SINCE" +%s)"
elif [[ -f "$SL_STATE/daily.cursor" ]]; then
  CUTOFF="$(tr -d '[:space:]' < "$SL_STATE/daily.cursor")"
else
  CUTOFF=$(( $(now_epoch) - $(cfg '.firstRunDays') * 86400 ))
fi

bash "$SL_SRC/prepare.sh" --cutoff "$CUTOFF" --archive-only
