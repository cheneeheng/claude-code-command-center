#!/usr/bin/env bash
# Fake `claude` for the tests. Never calls a model.
#
# Reads the prompt (last argument) and the staged input (stdin), then prints a
# preamble and one canned part per requested extraction. Controlled by files
# in its working directory, the meta repo, under .fake-claude/:
#   exit1      present: print an error and exit 1
#   exit1-stdout  present: print an error on stdout, as claude does for an
#              API error, and exit 1
#   fail.txt   lines "<extraction>:<uuid>": print a truncated part instead
#   none.txt   lines "<extraction>:<uuid>": print the "nothing found" form
#   calls.log  appended: "<uuid>: <requested extractions>" per call, or
#              "weekly: <first source file>" per weekly batch
#   weekly-answer.md   present: the weekly answer to give (after a preamble)
#   weekly-bad         present: give a malformed weekly answer; when it lists
#                      file names, only for a batch whose first source is listed
# The default weekly answer is one "## Tooling" section with two lessons named
# after the batch's first source file.
# The decisions merge ("# Weekly decisions merge") logs "weekly-decisions:
# <first source file>", saves its input as input-<first source file>, and
# answers a soul part and a questions part named after that file, unless:
#   weekly-decisions-answer.md   present: the answer to give
#   weekly-decisions-bad         present: give a malformed answer
#
# Cross-reference: tests/fake-claude.ps1 behaves the same.

prompt="${!#}"
input="$(cat)"
dir="$PWD/.fake-claude"; mkdir -p "$dir"
if [[ -e "$dir/exit1" ]]; then echo "fake claude: simulated failure" >&2; exit 1; fi
if [[ -e "$dir/exit1-stdout" ]]; then printf '\nAPI Error: 529 Overloaded.\n'; exit 1; fi

if [[ "$(head -n 1 <<<"$prompt")" == "# Weekly decisions merge" ]]; then
  first="$(sed -n 's/^## Source: //p' <<<"$input" | head -n 1)"
  echo "weekly-decisions: $first" >> "$dir/calls.log"
  printf '%s' "$input" > "$dir/input-$first"
  echo "Here is the merge."
  if [[ -e "$dir/weekly-decisions-bad" ]]; then echo "garbage"; exit 0; fi
  if [[ -e "$dir/weekly-decisions-answer.md" ]]; then cat "$dir/weekly-decisions-answer.md"; exit 0; fi
  printf '<<<extraction:soul>>>\n# SOUL\n\n## Priorities\n\n1. Synthetic priority from %s.\n\n## Rules\n\n- When synthetic, prefer %s.\n<<<extraction:questions>>>\n### Synthetic question from %s?\n\nContext: synthetic.\n' "$first" "$first" "$first"
  exit 0
fi

if [[ "$(head -n 1 <<<"$prompt")" == "# Weekly lessons merge" ]]; then
  first="$(sed -n 's/^## Source: //p' <<<"$input" | head -n 1)"
  echo "weekly: $first" >> "$dir/calls.log"
  echo "Here is the merge."
  if [[ -e "$dir/weekly-bad" ]] && { [[ ! -s "$dir/weekly-bad" ]] || grep -qxF "$first" "$dir/weekly-bad"; }; then
    echo "garbage"; exit 0
  fi
  if [[ -e "$dir/weekly-answer.md" ]]; then cat "$dir/weekly-answer.md"; exit 0; fi
  printf '## Tooling\n\n### Weekly lesson from %s\n**Source**: %s\n**Lesson**: A synthetic generic rule.\n**Apply when**: Always.\n**Tags**: #synthetic\n\n### Second weekly lesson from %s\n**Lesson**: Another synthetic rule.\n' "$first" "$first" "$first"
  exit 0
fi

uuid="$(sed -n 's/^UUID: //p' <<<"$input" | head -n 1)"
date="$(sed -n 's/^Date: //p' <<<"$input" | head -n 1)"
names="$(sed -n 's/^<<<extraction:\(.*\)>>>$/\1/p' <<<"$prompt" | tr '\n' ' ')"
echo "$uuid: ${names% }" >> "$dir/calls.log"

echo "Here are the parts you asked for."
for n in $names; do
  echo "<<<extraction:$n>>>"
  if grep -qx "$n:$uuid" "$dir/fail.txt" 2>/dev/null; then echo "truncated"; continue; fi
  header="$(printf '\xe2\x80\x94 %s\n**Session**: %s\n**Title**: Synthetic\n**Project**: synthetic' "$date" "$uuid")"
  if grep -qx "$n:$uuid" "$dir/none.txt" 2>/dev/null; then
    printf '# Decisions %s\n\n_No decisions extracted from this session._\n' "$header"; continue
  fi
  case "$n" in
    decisions) printf '# Decisions %s\n\n## Synthetic decision\n\n- **Situation:** A synthetic choice.\n- **Chosen:** Option A.\n- **Reason:** none given\n- **Reason source:** none\n' "$header" ;;
    lessons) printf '# Lessons \xe2\x80\x94 %s\n**Session**: %s\n**Title**: Synthetic\n**Project**: synthetic\n\n## %s \xe2\x80\x94 Synthetic lesson\n\n**What happened:** A synthetic mistake.\n\n**Lesson:** A synthetic rule.\n' "$date" "$uuid" "$date" ;;
    *) echo "$n part for $uuid" ;;
  esac
done
