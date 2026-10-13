#!/usr/bin/env bash
# Fake `gh` for the tests. Never reaches GitHub.
#
# Answers from canned JSON in its working directory (the meta repo), under
# .fake-gh/:
#   user.json   `api user`   (default {"login":"synth-owner"})
#   repo.json   `repo view`  (default {"visibility":"PRIVATE"})
#   closed.json, all.json, open.json   `issue list --state <state>` (default [])
#   fail        present: every call exits 1
# `issue list` honours --limit the way gh does (30 when not given). Every call
# is logged to calls.log as its arguments, the --body value left out; each
# `issue create` title is also appended to created.txt.
#
# Cross-reference: tests/fake-gh.ps1 behaves the same.

dir="$PWD/.fake-gh"; mkdir -p "$dir"
args=("$@"); logged=(); limit=30; state=""; title=""
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    --body) i=$((i + 1)); continue ;;
    --limit) limit="${args[$((i + 1))]}" ;;
    --state) state="${args[$((i + 1))]}" ;;
    --title) title="${args[$((i + 1))]}" ;;
  esac
  logged+=("${args[$i]}")
done
echo "${logged[*]}" >> "$dir/calls.log"
if [[ -e "$dir/fail" ]]; then echo "fake gh: simulated failure" >&2; exit 1; fi

JQ=(jq); jq --binary -n 1 >/dev/null 2>&1 && JQ=(jq --binary)
case "$1 $2" in
  "api user") cat "$dir/user.json" 2>/dev/null || echo '{"login":"synth-owner"}' ;;
  "repo view") cat "$dir/repo.json" 2>/dev/null || echo '{"visibility":"PRIVATE"}' ;;
  "label create") echo "Label created." ;;
  "issue list") if [[ -f "$dir/$state.json" ]]; then "${JQ[@]}" -c --argjson n "$limit" '.[:$n]' "$dir/$state.json"; else echo '[]'; fi ;;
  "issue create") echo "$title" >> "$dir/created.txt"; echo "https://github.com/synth-owner/synth-meta/issues/99" ;;
esac
exit 0
