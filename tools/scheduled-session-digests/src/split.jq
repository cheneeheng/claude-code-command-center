# split.jq: splits one claude answer (read whole, with -Rs) into its parts.
# $names: JSON array of the requested extraction names.
# Output: {"<name>": "<part>\n", ...} for each requested name that has a part.
#
# Rules: a marker counts only as a whole line `<<<extraction:NAME>>>`; text
# before the first marker is ignored; parts for names not requested are
# ignored; when a name appears twice, the first part wins. A part is trimmed,
# and a markdown fence wrapped around the whole part is dropped.
#
# Cross-reference: Split-Answer in src/lib.ps1 implements the same rules.

def trimws: sub("^[ \t\n\r\u000b\u000c]+"; "") | sub("[ \t\n\r\u000b\u000c]+$"; "");
def unfence: if test("^```[^\n]*\n") and test("\n```$")
  then sub("^```[^\n]*\n"; "") | sub("\n```$"; "") | trimws else . end;

reduce (split("\n")[] | sub("\r$"; "")) as $line ({cur: null, parts: {}};
  ([$line | capture("^<<<extraction:(?<n>[A-Za-z0-9_-]+)>>>$") | .n] | first) as $m
  | if $m != null then
      .cur = (if ($names | index($m)) != null and (.parts | has($m) | not) then $m else "" end)
      | if .cur != "" then .parts[.cur] = [] else . end
    elif .cur != null and .cur != "" then .parts[.cur] += [$line]
    else . end)
| .parts | map_values(join("\n") | trimws | unfence | . + "\n")
