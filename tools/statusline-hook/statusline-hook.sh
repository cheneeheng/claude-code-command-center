#!/usr/bin/env bash
# Claude Code statusline (bash port). Needs jq.
#
#   Opus 5.5 high   ctx ━━━━────── 42% · ◷ 1h 12m · $1.23
#                   5h  ━━━━━━──── 63%  ↺ 16:00 (7h 6m)
#                   7d  ━━━━━━━━── 85%  ↺ Thu 16:00 (5d 7h)
#
# Reads the JSON Claude Code pipes to stdin. A rate-limit row is shown only when Claude Code
# sends that window. Bad input prints nothing. The render spec is the fixtures/ folder;
# statusline-hook.ps1 must produce the same bytes.
#
# Setup: "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-hook.sh" }

# One jq program renders everything, so a turn costs one process and no `date` portability.
# tr drops the \r that jq on Windows writes before each \n.
jq -rj '
  def c($n): "\u001b[\($n)m";
  def rep($s; $n): [range($n) | $s] | add // "";
  def level: if . < 50 then c(32) elif . < 80 then c(33) else c(31) end;
  def gauge:
    ((. // 0) | floor) as $p
    | ([[$p, 0] | max, 100] | min | . * 10 / 100 | floor) as $f
    | ($p | level) as $l
    | $l + rep("━"; $f) + c(0) + c(2) + rep("─"; 10 - $f) + c(0)
      + " " + $l + "\($p)%" + c(0);
  # Time left until a reset, e.g. "5d 7h", "7h 6m", "12m".
  def left:
    ([., 0] | max | floor) as $s
    | ($s / 86400 | floor) as $d | (($s % 86400) / 3600 | floor) as $h
    | (($s % 3600) / 60 | floor) as $m
    | if $d > 0 then "\($d)d \($h)h" elif $h > 0 then "\($h)h \($m)m" else "\($m)m" end;
  def reset($day; $now):
    if (. // 0) > 0 then
      (floor | localtime) as $t
      | "  " + c(2) + "↺ "
        + (if $day then ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][$t[6]] + " " else "" end)
        + ($t | strftime("%H:%M")) + " (" + (. - $now | left) + ")" + c(0)
    else "" end;
  def runtime:
    ((. // 0) / 1000 | floor) as $s
    | ($s / 3600 | floor) as $h | (($s % 3600) / 60 | floor) as $m
    | if $h > 0 then "\($h)h \($m)m" else "\($m)m" end;
  def cost:
    ((. // 0) * 100 + 0.5 | floor) as $c
    | "\($c / 100 | floor)." + ($c % 100 | tostring | if length < 2 then "0" + . else . end);
  def row($label; $w; $indent; $day; $now):
    $indent + c(2) + $label + c(0) + "  " + ($w.used_percentage | gauge)
    + ($w.resets_at | reset($day; $now));

  objects
  # C4_STATUSLINE_NOW (epoch seconds) pins the clock for the golden tests only.
  | ($ENV.C4_STATUSLINE_NOW // now | tonumber) as $now
  | (.model.display_name // "") as $model
  | (.effort.level // "" | tostring) as $effort
  | ($model + (if $effort != "" then " " + $effort else "" end) | length) as $width
  # Claude Code trims leading whitespace from each row, so the indent opens with U+2800
  # (Braille blank): it renders as an empty cell but is not whitespace.
  | ("⠀" + rep(" "; $width + 2)) as $indent
  | (" " + c(2) + "·" + c(0) + " ") as $sep
  | [ c(1) + c(36) + $model + c(0)
        + (if $effort != "" then " " + c(36) + $effort + c(0) else "" end)
        + "   " + c(2) + "ctx" + c(0) + " "
        + (.context_window.used_percentage | gauge)
        + $sep + c(2) + "◷" + c(0) + " " + (.cost.total_duration_ms | runtime)
        + $sep + "$" + (.cost.total_cost_usd | cost),
      (.rate_limits.five_hour // empty | row("5h"; .; $indent; false; $now)),
      (.rate_limits.seven_day // empty | row("7d"; .; $indent; true; $now))
    ]
  | join("\n") + "\n"
' 2>/dev/null | tr -d '\r'
exit 0
