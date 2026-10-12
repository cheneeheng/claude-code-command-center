# clean.jq: turns one Claude Code session transcript (JSONL, read with -R) into
# the cleaned conversation the extractions read. Cleanup rules version: v1.
#
# Output: {title, project, turns, body}. body is a sequence of blocks, each
# "[LABEL]\n<text>\n\n" (or "[LABEL]\n\n" when there is no text).
#
# Cross-reference: Convert-Transcript in src/lib.ps1 implements the same rules.
# Any change here must be made there too, and bumps the Cleanup version.

def trimws: sub("^[ \t\n\r\u000b\u000c]+"; "") | sub("[ \t\n\r\u000b\u000c]+$"; "");

# Text injected by the harness or hooks; never the user's own words.
def removed_tags: "system-reminder", "task-notification", "command-message",
  "local-command-stdout", "local-command-stderr", "local-command-caveat",
  "bash-stdout", "bash-stderr";

# Tags around text the user did type: keep the inside.
def unwrapped_tags: "command-name", "command-args", "bash-input";

def usertext:
  reduce removed_tags as $t (.; gsub("<" + $t + ">[\\s\\S]*?</" + $t + ">"; ""))
  | reduce unwrapped_tags as $t (.; gsub("<" + $t + ">(?<x>[\\s\\S]*?)</" + $t + ">"; .x))
  | trimws;

def interrupts: ["[Request interrupted by user]", "[Request interrupted by user for tool use]"];

def block($label; $text): "[" + $label + "]\n" + (if $text == "" then "" else $text + "\n" end) + "\n";

def textof: if type == "string" then .
  elif type == "array" then [ .[] | select(.type == "text") | .text // "" ] | join("\n")
  else "" end;

# Adds a user-typed text to the state: an interrupt notice or a [USER] turn.
def add_user($s):
  if ($s | trimws) as $r | interrupts | index($r) then .out += block("INTERRUPTED"; "")
  else ($s | usertext) as $t
    | if $t == "" then . else .out += block("USER"; $t) | .turns += 1 end
  end;

def answer_text($e):
  ($e.toolUseResult.annotations // {}) as $ann
  | [ $e.toolUseResult.answers | to_entries[]
      | "Q: " + .key + "\nA: "
        + (.value | if type == "array" then map(tostring) | join(", ") else tostring end)
        + (($ann[.key].notes // "") as $n | if ($n | type) == "string" and $n != "" then "\nNotes: " + $n else "" end)
    ] | join("\n");

def add_tool_result($e; $b):
  .tools[$b.tool_use_id // ""] as $name
  | if $name == "AskUserQuestion" then
      (if ($e.toolUseResult | type) == "object" and ($e.toolUseResult.answers | type) == "object"
       then answer_text($e) else ($b.content | textof | trimws) end) as $a
      | if $a == "" then . else .out += block("ANSWER"; $a) | .turns += 1 end
    elif $e.toolUseResult == "User rejected tool use" then
      .out += block("USER REJECTED " + ($name // "unknown"); "")
    else . end;

def add_user_entry($e):
  ($e.message.content) as $c
  | if ($c | type) == "array" then
      reduce ($c[] | select(.type == "tool_result")) as $b (.; add_tool_result($e; $b))
      | if ([ $c[] | select(.type == "text") ] | length) > 0 then add_user($c | textof) else . end
    else add_user($c | textof) end;

def add_question($q):
  .out += block("QUESTION";
    ($q.question // "") + "\nOptions:\n"
    + ([ ($q.options // [])[]
         | "- " + (.label // "") + (if (.description // "") != "" then ": " + .description else "" end)
       ] | join("\n")));

def add_assistant_entry($e):
  reduce (($e.message.content // []) | if type == "string" then [{type: "text", text: .}] else . end)[] as $b (.;
    if $b.type == "text" then
      ($b.text // "" | trimws) as $t
      | if $t == "" then .
        else .out += block("ASSISTANT"; if ($t | length) > 10000 then $t[0:10000] + "\n[...truncated]" else $t end)
        end
    elif $b.type == "tool_use" then
      .tools[$b.id // ""] = ($b.name // "")
      | if $b.name == "AskUserQuestion"
        then reduce ($b.input.questions // [])[] as $q (.; add_question($q)) else . end
    else . end);

reduce (inputs | fromjson? | select(type == "object")) as $e (
  {title: null, cwd: null, turns: 0, out: "", tools: {}};
  (if .title == null and $e.type == "custom-title" and ($e.customTitle | type) == "string" and $e.customTitle != ""
   then .title = $e.customTitle else . end)
  | (if .cwd == null and ($e.cwd | type) == "string" and $e.cwd != "" then .cwd = $e.cwd else . end)
  | if $e.isSidechain == true then .
    elif $e.type == "user" then
      if $e.isMeta == true or $e.isCompactSummary == true then . else add_user_entry($e) end
    elif $e.type == "assistant" then add_assistant_entry($e)
    elif $e.type == "attachment" and $e.attachment.type == "queued_command"
         and $e.attachment.humanTurn == true and ($e.attachment.prompt | type) == "string" then
      add_user($e.attachment.prompt)
    else . end
)
| {
    title,
    project: (if .cwd == null then "unknown"
              else (.cwd | sub("[/\\\\]+$"; "") | [splits("[/\\\\]")] | map(select(. != "")) | last // "unknown") end),
    turns,
    body: .out
  }
