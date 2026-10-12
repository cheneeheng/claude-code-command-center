#!/usr/bin/env bash
# git-sync.sh: the only writer of git history in the meta repo. Stages every
# change, makes one commit, and pushes when a remote exists.
#
# Usage: git-sync.sh <job> [<log>]    Prints "<committed> <pushed> <error>": two
# true/false values, then the error line (empty when the commit went through).
#
# Cross-reference: src/git-sync.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SL_LOG="${2:-}"

committed=false; pushed=false; error=""
if [[ -d "$SL_META/.git" ]]; then
  # A failed add or commit is the run's error; a failed push is only a warning,
  # because the commit is safe and the next run pushes it.
  if ! out="$(git -C "$SL_META" add -A 2>&1)"; then
    error="git commit failed: $(grep -m 1 -v '^[[:space:]]*$' <<<"$out" || true)"
  elif ! git -C "$SL_META" diff --cached --quiet; then
    if out="$(git -C "$SL_META" commit -q -m "lessons($1): $(date '+%Y-%m-%d %H:%M')" 2>&1)"; then committed=true
    else error="git commit failed: $(grep -m 1 -v '^[[:space:]]*$' <<<"$out" || true)"; fi
  fi
  if [[ -n "$(git -C "$SL_META" remote)" ]]; then
    # stdout carries the result, so the warning goes to stderr and the log.
    if git -C "$SL_META" push -q >/dev/null 2>&1; then pushed=true
    else say "git push failed; the commit stays local." >&2; fi
  fi
fi
echo "$committed $pushed $error"
