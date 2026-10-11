#!/usr/bin/env bash
# git-sync.sh: the only writer of git history in the meta repo. Stages every
# change, makes one commit, and pushes when a remote exists.
#
# Usage: git-sync.sh <job> [<log>]    Prints "<committed> <pushed>" as true/false.
#
# Cross-reference: src/git-sync.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SL_LOG="${2:-}"

committed=false; pushed=false
if [[ -d "$SL_META/.git" ]]; then
  git -C "$SL_META" add -A
  if ! git -C "$SL_META" diff --cached --quiet; then
    git -C "$SL_META" commit -q -m "lessons($1): $(date '+%Y-%m-%d %H:%M')" && committed=true
  fi
  if [[ -n "$(git -C "$SL_META" remote)" ]]; then
    # stdout carries the result, so the warning goes to stderr and the log.
    if git -C "$SL_META" push -q >/dev/null 2>&1; then pushed=true
    else say "git push failed; the commit stays local." >&2; fi
  fi
fi
echo "$committed $pushed"
