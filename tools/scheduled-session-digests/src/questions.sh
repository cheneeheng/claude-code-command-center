#!/usr/bin/env bash
# questions.sh: the question queue, GitHub issues on the meta repo's origin.
#
# Usage: questions.sh collect|open|count --ext <name> [--log <file>]
#   collect  writes <outputDir>/answered/issue-<n>.md for each closed issue with
#            the extraction's label that has a comment by the repo owner and no
#            such file yet. Prints the warning (empty when none).
#   open     opens an issue for every "### " question in <outputDir>/questions/
#            whose title no issue with the label has, on a PRIVATE repo only.
#            Prints two lines: <owner/repo> when the queue is active on a
#            private repo (else empty), then the warning (empty when none).
#   count    prints the number of open issues with the label, or "unknown".
# The queue is active when weekly.questions.enabled is true, install recorded a
# ghPath, and origin is a GitHub URL. Otherwise each mode logs one line and does
# nothing. Messages go to stderr and the log: stdout carries the result.
#
# Cross-reference: src/questions.ps1 is the PowerShell twin.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:?usage: questions.sh collect|open|count --ext <name>}"; shift
EXT=""
while (( $# )); do
  case "$1" in
    --ext) EXT="$2"; shift 2 ;;
    --log) SL_LOG="$2"; shift 2 ;;
    *) echo "questions: unknown argument $1" >&2; exit 1 ;;
  esac
done

OUT="$(cfg ".extractions[\"$EXT\"].outputDir")"
LABEL="$(cfg ".extractions[\"$EXT\"].weekly.questions.label // \"decision-question\"")"
GH="$(inst_get '.ghPath // empty')"
url="$(git -C "$SL_META" remote get-url origin 2>/dev/null || true)"
REPO=""
if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"; fi
OWNER="${REPO%%/*}"

off=""
if [[ "$(cfg ".extractions[\"$EXT\"].weekly.questions.enabled // false")" != true ]]; then off="questions are off in config"
elif [[ -z "$GH" ]] || ! { [[ -e "$GH" ]] || command -v "$GH" >/dev/null 2>&1; }; then off="gh not found (re-run install after installing it)"
elif [[ -z "$REPO" ]]; then off="origin is not a GitHub repo"; fi
if [[ -n "$off" ]]; then
  [[ "$MODE" == count ]] || say "Question queue off: $off." >&2
  case "$MODE" in collect) echo "" ;; open) printf '\n\n' ;; count) echo unknown ;; esac
  exit 0
fi

# gh's stderr goes to a file, so a failure's warning can name gh's own error.
GHERR="$(mktemp)"; trap 'rm -f "$GHERR"' EXIT
gh_() { (cd "$SL_META" && "$GH" "$@") 2> "$GHERR"; }
gh_err() { local e; e="$(grep -m 1 -v '^[[:space:]]*$' "$GHERR" || true)"; if [[ -n "$e" ]]; then printf ': %s' "$e"; fi; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
TRIM='def trimws: sub("^[ \t\n\r\u000b\u000c]+"; "") | sub("[ \t\n\r\u000b\u000c]+$"; "");'

if [[ "$MODE" == count ]]; then
  if j="$(gh_ issue list --repo "$REPO" --state open --label "$LABEL" --limit 1000 --json number 2>/dev/null)"; then
    "${JQ[@]}" 'length' <<<"$j"
  else echo unknown; fi
  exit 0
fi

# Both modes need the label: gh issue create fails on a missing one.
if ! gh_ label create "$LABEL" --repo "$REPO" --force >/dev/null 2>&1; then
  w="questions $MODE: gh label create failed$(gh_err)"; say "$w" >&2
  [[ "$MODE" == open ]] && printf '\n%s\n' "$w" || echo "$w"
  exit 0
fi

if [[ "$MODE" == collect ]]; then
  if ! user="$(gh_ api user 2>/dev/null)" || ! closed="$(gh_ issue list --repo "$REPO" --state closed --label "$LABEL" \
       --limit 1000 --json number,title,body,comments 2>/dev/null)"; then
    w="questions collect: gh failed$(gh_err)"; say "$w" >&2; echo "$w"; exit 0
  fi
  if [[ "$(lower "$("${JQ[@]}" -r .login <<<"$user")")" != "$(lower "$OWNER")" ]]; then
    w="questions collect: gh is signed in as someone other than $OWNER, no answers read"
    say "$w" >&2; echo "$w"; exit 0
  fi
  dir="$SL_META/$OUT/answered"; n_new=0
  while IFS=$'\t' read -r num; do
    [[ -f "$dir/issue-$num.md" ]] && continue
    text="$("${JQ[@]}" -r --argjson n "$num" --arg o "$(lower "$OWNER")" "$TRIM"'
      .[] | select(.number == $n)
      | [.comments[]? | select((.author.login // "" | ascii_downcase) == $o) | .body // "" | gsub("\r"; "") | trimws
         | select(. != "")] as $r
      | if ($r | length) == 0 then empty else
          "## \(.title | gsub("\r"; "") | trimws)\n\n**Issue:** #\(.number)\n\n### Situation\n\n"
          + (.body // "" | gsub("\r"; "") | trimws | if . == "" then "(no description)" else . end)
          + "\n\n### Reason\n\n" + ($r | join("\n\n")) + "\n\n**Reason source:** stated" end' <<<"$closed")"
    [[ -n "$text" ]] || continue
    mkdir -p "$dir"; printf '%s\n' "$text" > "$dir/issue-$num.md"; n_new=$((n_new + 1))
  done < <("${JQ[@]}" -r '.[].number' <<<"$closed")
  say "Questions: $n_new answer(s) read from closed issues." >&2
  echo ""
  exit 0
fi

# --- open ------------------------------------------------------------------------
if ! repo="$(gh_ repo view "$REPO" --json visibility 2>/dev/null)"; then
  w="questions open: gh failed$(gh_err)"; say "$w" >&2; printf '\n%s\n' "$w"; exit 0
fi
if [[ "$("${JQ[@]}" -r .visibility <<<"$repo")" != PRIVATE ]]; then
  w="questions open: $REPO is not private, no issues opened"; say "$w" >&2; printf '\n%s\n' "$w"; exit 0
fi
if ! all="$(gh_ issue list --repo "$REPO" --state all --label "$LABEL" --limit 1000 --json title 2>/dev/null)"; then
  w="questions open: gh failed$(gh_err)"; say "$w" >&2; printf '\n%s\n' "$w"; exit 0
fi
declare -A HAVE=()
while IFS= read -r t; do HAVE["$t"]=1; done < <("${JQ[@]}" -r '.[].title' <<<"$all")
w=""; n_new=0
qd="$SL_META/$OUT/questions"
if [[ -d "$qd" ]]; then
  while IFS= read -r f; do
    # Each "### " line starts a question; the lines up to the next one are its body.
    while IFS= read -r q; do
      title="$("${JQ[@]}" -r .title <<<"$q")"
      [[ -n "$title" && -z "${HAVE[$title]:-}" ]] || continue
      HAVE["$title"]=1
      if gh_ issue create --repo "$REPO" --label "$LABEL" --title "$title" --body "$("${JQ[@]}" -r .body <<<"$q")" >/dev/null 2>&1; then
        n_new=$((n_new + 1))
      else w="questions open: gh issue create failed$(gh_err)"; fi
    done < <("${JQ[@]}" -Rsc "$TRIM"'
      split("\n") | map(sub("\r$"; ""))
      | reduce .[] as $l ([]; if ($l | startswith("### ")) then . + [{title: ($l[4:] | trimws), body: []}]
                              elif length > 0 then .[-1].body += [$l] else . end)
      | .[] | .body |= (join("\n") | trimws)' "$f")
  done < <(find "$qd" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
fi
say "Questions: $n_new issue(s) opened on $REPO." >&2
printf '%s\n%s\n' "$REPO" "$w"
