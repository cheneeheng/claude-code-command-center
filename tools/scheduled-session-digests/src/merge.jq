# merge.jq: merges one weekly lessons answer into the master lessons file.
# Run with: jq -n --rawfile answer <file> --rawfile master <file or empty>
#               --arg date <yyyy-mm-dd> --argjson categories <json array>
# Output: {status: "none"|"merged"|"invalid", added: <n>, merged: <text>}
#
# Rules:
# - The answer is trimmed and a fence around it dropped. Text before the first
#   "## " line is ignored. With no "## " line, an answer holding the line
#   "_No new lessons._" means none; anything else is invalid.
# - Each "### " line starts a lesson under the latest "## " category. A lesson
#   needs a "**Lesson**:" line; its category must be in $categories or already a
#   "## " section of the master. At least one lesson is needed.
# - A lesson whose "### " title is already in the master, or earlier in the same
#   answer, is skipped. Each one is appended at the end of its category section;
#   a missing category is added at the end of the file.
# - With at least one lesson added, "Last updated:" becomes $date. With none
#   added, the status is "none" and the master is left as it is.
#
# Cross-reference: Merge-WeeklyAnswer in src/lib.ps1 implements the same rules.

def trimws: sub("^[ \t\n\r\u000b\u000c]+"; "") | sub("[ \t\n\r\u000b\u000c]+$"; "");
def unfence: if test("^```[^\n]*\n") and test("\n```$")
  then sub("^```[^\n]*\n"; "") | sub("\n```$"; "") | trimws else . end;
def droptrailingblank: until(length == 0 or .[-1] != ""; .[:-1]);

def insert($cat; $block):
  . as $L
  | ([range(0; $L | length) | select($L[.] == "## " + $cat)] | first) as $h
  | if $h == null then ($L | droptrailingblank) + ["", "## " + $cat, ""] + $block
    else
      ([range($h + 1; $L | length) | select($L[.] | startswith("## "))] | first // ($L | length)) as $e
      | ($e | until(. - 1 <= $h or $L[. - 1] != ""; . - 1)) as $p
      | $L[:$p] + [""] + $block + (if $p == $e and $e < ($L | length) then [""] else [] end) + $L[$p:]
    end;

($answer | trimws | unfence | split("\n") | map(sub("\r$"; ""))) as $a
| (if $master == "" then
     ["# Master Lessons Learned", "", "Cross-project lessons harvested weekly from daily session notes.", "Last updated: " + $date]
   else $master | split("\n") | map(sub("\r$"; "")) | droptrailingblank end) as $m
| ([$m[] | select(startswith("### "))]) as $oldTitles
| ([$m[] | select(startswith("## ")) | .[3:]]) as $masterCats
| ([range(0; $a | length) | select($a[.] | startswith("## "))] | first) as $start
| if $start == null then
    {status: (if any($a[]; . == "_No new lessons._") then "none" else "invalid" end), added: 0, merged: ""}
  else
    (reduce $a[$start:][] as $line ({cat: null, lessons: []};
       if $line | startswith("### ") then .lessons += [{cat: .cat, lines: [$line | sub("[ \t]+$"; "")]}]
       elif $line | startswith("## ") then .cat = ($line[3:] | trimws)
       elif (.lessons | length) > 0 then .lessons[-1].lines += [$line | sub("[ \t]+$"; "")]
       else . end)
     | .lessons | map(.lines |= droptrailingblank)) as $lessons
    | if ($lessons | length) == 0
         or any($lessons[]; . as $l | $l.cat == null
                             or ((($categories + $masterCats) | index([$l.cat])) == null)
                             or (any($l.lines[]; startswith("**Lesson**:")) | not))
      then {status: "invalid", added: 0, merged: ""}
      else
        (reduce $lessons[] as $l ({lines: $m, seen: $oldTitles, added: 0};
           if (.seen | index([$l.lines[0]])) != null then .
           else .lines |= insert($l.cat; $l.lines) | .seen += [$l.lines[0]] | .added += 1 end)) as $r
        | if $r.added == 0 then {status: "none", added: 0, merged: ""}
          else
            ([range(0; $r.lines | length) | select($r.lines[.] | startswith("Last updated: "))] | first) as $u
            | ($r.lines | if $u == null then . else .[$u] = "Last updated: " + $date end) as $out
            | if ($out[0] | startswith("# Master Lessons Learned")) and all($oldTitles[]; . as $t | $out | index([$t]) != null)
              then {status: "merged", added: $r.added, merged: (($out | join("\n")) + "\n")}
              else {status: "invalid", added: 0, merged: ""} end
          end
      end
  end
