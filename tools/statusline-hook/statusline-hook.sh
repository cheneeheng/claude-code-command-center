#!/usr/bin/env bash
# Claude Code statusline (bash port). Needs jq.
#
#   Opus 5.5 high | ⏳ 36m | 📋 42% | 5h 63% 🔄 7h 6m | 7d 85% 🔄 5d 7h | 🕒 1h 12m | $1.23
#
# Reads the JSON Claude Code pipes to stdin. A rate-limit segment is shown only when Claude Code
# sends that window. Bad input prints nothing. The render spec is the fixtures/ folder;
# statusline-hook.ps1 must produce the same bytes.
#
# Setup: "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-hook.sh" }

# The prompt cache expiry needs the transcript: a first jq pulls its path, and the transcript
# tail is piped to the render as raw lines. One more jq program renders everything, so there
# is no `date` portability. tr drops the \r that jq on Windows writes before each \n.
input="$(cat)"
transcript="$(jq -r '.transcript_path? // empty' <<<"$input" 2>/dev/null)"
transcript="${transcript%$'\r'}"
# less-code: only the last 100 transcript lines are scanned. If the last main-session reply
# is further back, the cache segment is left out.
{ [ -n "$transcript" ] && tail -n 100 "$transcript" 2>/dev/null; } |
jq -nRrj --argjson d "$input" '
  def c($n): "\u001b[\($n)m";
  def rep($s; $n): [range($n) | $s] | add // "";
  def level: if . < 50 then c(32) elif . < 80 then c(33) else c(31) end;
  # Percentage right-aligned in three characters, coloured by level.
  def pct:
    ((. // 0) | floor) as $p
    | ($p | level) + ("\($p)" | rep(" "; 3 - length) + .) + "%" + c(0);
  # Time left until a reset, e.g. "5d 7h", "7h 6m", "12m".
  def left:
    ([., 0] | max | floor) as $s
    | ($s / 86400 | floor) as $d | (($s % 86400) / 3600 | floor) as $h
    | (($s % 3600) / 60 | floor) as $m
    | if $d > 0 then "\($d)d \($h)h" elif $h > 0 then "\($h)h \($m)m" else "\($m)m" end;
  def reset($now):
    if (. // 0) > 0 then " 🔄 " + (floor - $now | left) else "" end;
  def runtime:
    ((. // 0) / 1000 | floor) as $s
    | ($s / 3600 | floor) as $h | (($s % 3600) / 60 | floor) as $m
    | if $h > 0 then "\($h)h \($m)m" else "\($m)m" end;
  def cost:
    ((. // 0) * 100 + 0.5 | floor) as $c
    | "\($c / 100 | floor)." + ($c % 100 | tostring | if length < 2 then "0" + . else . end);
  def seg($label; $w; $now):
    c(1) + $label + c(0) + ($w.used_percentage | pct) + ($w.resets_at | reset($now));

  # The main session caches its prompt for one hour after its last API reply. Synthetic
  # replies never reached the API, and sidechain replies belong to subagents.
  def cache($now):
    (.[0:19] + "Z" | fromdateiso8601 + 3600) as $end
    | "⏳ "
      + if $end > $now then ($end - $now | left) else "expired" end;

  [inputs | fromjson? | objects
    | select(.type == "assistant" and .isSidechain != true
             and .message.model != "<synthetic>")
    | .timestamp | strings] | last as $cached
  | $d | objects
  # C4_STATUSLINE_NOW (epoch seconds) pins the clock for the golden tests only.
  | ($ENV.C4_STATUSLINE_NOW // now | tonumber) as $now
  | (.model.display_name // "") as $model
  | (.effort.level // "" | tostring) as $effort
  | (" " + c(1) + "|" + c(0) + " ") as $sep
  # Segments are joined by the separator, so an absent one leaves no stray separator.
  | [ c(1) + c(36) + $model + c(0)
        + (if $effort != "" then " " + c(36) + $effort + c(0) else "" end),
      (($cached // empty | try cache($now)) // ""),
      "📋" + (.context_window.used_percentage | pct),
      ((.rate_limits.five_hour // empty | seg("5h"; .; $now)) // ""),
      ((.rate_limits.seven_day // empty | seg("7d"; .; $now)) // ""),
      "🕒 " + (.cost.total_duration_ms | runtime),
      "$" + (.cost.total_cost_usd | cost)
    ]
  | map(select(. != "")) | join($sep) + "\n"
' 2>/dev/null | tr -d '\r'

# Quota export, on unless C4_STATUSLINE_DISABLE_EXPORT is on: hooks never receive rate_limits, so
# the latest reading is relayed to one file for readers such as the ceh-every-session usage-limit
# guard. Written after the statusline is printed, through a temp file and a rename, so a reader
# never sees half a line and a failure never changes the output.
case "${C4_STATUSLINE_DISABLE_EXPORT:-}" in
  1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss]) ;;
  *)
    dir="$HOME/.claude/statusline/latest"
    line="$(jq -c 'select(.rate_limits | type == "object" and length > 0)
      | {session_id, ts: (now * 1000 | floor), data: {rate_limits}}' <<<"$input" 2>/dev/null |
      tr -d '\r')"
    if [ -n "$line" ] && mkdir -p "$dir" 2>/dev/null; then
      tmp="$dir/rate-limits.jsonl.$$.tmp"
      { printf '%s\n' "$line" >"$tmp" && mv -f "$tmp" "$dir/rate-limits.jsonl"; } 2>/dev/null ||
        rm -f "$tmp" 2>/dev/null
    fi
    ;;
esac
exit 0
