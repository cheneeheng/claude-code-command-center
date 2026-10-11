#!/usr/bin/env bash
# Fake `claude` for the tests. Never calls a model.
#
# Reads the prompt (last argument) and the staged input (stdin), then prints a
# preamble and one canned part per requested extraction. Controlled by files
# in its working directory, the meta repo, under .fake-claude/:
#   exit1      present: print an error and exit 1
#   fail.txt   lines "<extraction>:<uuid>": print a truncated part instead
#   calls.log  appended: "<uuid>: <requested extractions>" per call
#
# Cross-reference: tests/fake-claude.ps1 behaves the same.

prompt="${!#}"
input="$(cat)"
dir="$PWD/.fake-claude"; mkdir -p "$dir"
if [[ -e "$dir/exit1" ]]; then echo "fake claude: simulated failure" >&2; exit 1; fi

uuid="$(sed -n 's/^UUID: //p' <<<"$input" | head -n 1)"
date="$(sed -n 's/^Date: //p' <<<"$input" | head -n 1)"
names="$(sed -n 's/^<<<extraction:\(.*\)>>>$/\1/p' <<<"$prompt" | tr '\n' ' ')"
echo "$uuid: ${names% }" >> "$dir/calls.log"

echo "Here are the parts you asked for."
for n in $names; do
  echo "<<<extraction:$n>>>"
  if grep -qx "$n:$uuid" "$dir/fail.txt" 2>/dev/null; then echo "truncated"; continue; fi
  case "$n" in
    lessons) printf '# Lessons \xe2\x80\x94 %s\n**Session**: %s\n**Title**: Synthetic\n**Project**: synthetic\n\n## %s \xe2\x80\x94 Synthetic lesson\n\n**What happened:** A synthetic mistake.\n\n**Lesson:** A synthetic rule.\n' "$date" "$uuid" "$date" ;;
    *) echo "$n part for $uuid" ;;
  esac
done
