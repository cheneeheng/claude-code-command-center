#!/bin/bash
input=$(cat)

# --- Extract fields ---
MODEL=$(echo "$input" | jq -r '.model.id')

DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

#PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
#PCT=$(($(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1) * 5))
RAW=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
if [ "$SIZE" -eq 1000000 ]; then
    PCT=$(( RAW * 5 ))
else
    PCT=$RAW
fi

RATE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | xargs printf '%.0f')
RESET_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
RATE_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | xargs printf '%.0f')
RESET_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')

# --- Format runtime ---
DURATION_SEC=$((DURATION_MS / 1000))
HOURS=$((DURATION_SEC / 3600))
MINS=$(((DURATION_SEC % 3600) / 60))
SECS=$((DURATION_SEC % 60))
if [ "$HOURS" -gt 0 ]; then
  RUNTIME="${HOURS}h ${MINS}m ${SECS}s"
else
  RUNTIME="${MINS}m ${SECS}s"
fi

# --- Format cost ---
COST_FMT=$(printf '$%.4f' "$COST")

# --- Build context bar (▓ filled, ░ empty) ---
BAR_WIDTH=10
PCT_CAPPED=$((PCT > 100 ? 100 : PCT))
FILLED=$((PCT_CAPPED * BAR_WIDTH / 100))
#FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /▓}"
[ "$EMPTY"  -gt 0 ] && printf -v PAD  "%${EMPTY}s"  && BAR="${BAR}${PAD// /░}"

# --- Format rate limit reset times ---
if [ "$RESET_5H" -gt 0 ]; then
  RESET_5H_FMT=$(date -d "@$RESET_5H" '+%H:%M' 2>/dev/null || date -r "$RESET_5H" '+%H:%M' 2>/dev/null || echo "--:--")
else
  RESET_5H_FMT="--:--"
fi
if [ "$RESET_7D" -gt 0 ]; then
  RESET_7D_FMT=$(date -d "@$RESET_7D" '+%a %H:%M' 2>/dev/null || date -r "$RESET_7D" '+%a %H:%M' 2>/dev/null || echo "---")
else
  RESET_7D_FMT="---"
fi

# --- ANSI colors ---
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET_COLOR='\033[0m'

# Context: green <30, yellow 30-49, red >=50
if [ "$PCT" -lt 30 ]; then
  CTX_COLOR="$GREEN"
elif [ "$PCT" -lt 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$RED"
fi

# Rate limits: green <30, yellow 30-69, red >=70
rate_color() {
  local r=$1
  if [ "$r" -lt 30 ]; then
    echo "$GREEN"
  elif [ "$r" -lt 70 ]; then
    echo "$YELLOW"
  else
    echo "$RED"
  fi
}
COLOR_5H=$(rate_color "$RATE_5H")
COLOR_7D=$(rate_color "$RATE_7D")

# --- Single-line output ---
printf "${MODEL} | ${CTX_COLOR}${BAR} ${PCT}%%${RESET_COLOR} | ${RUNTIME} | ${COST_FMT} | ${COLOR_5H}5H: ${RATE_5H}%% (↺ ${RESET_5H_FMT})${RESET_COLOR} | ${COLOR_7D}7D: ${RATE_7D}%% (↺ ${RESET_7D_FMT})${RESET_COLOR}\n"

# --- Log to per-project statusline/project_name/$session_id.jsonl (opt-in) ---
# Export is off unless C4_STATUSLINE_EXPORT is 1/true/yes.
case "$(echo "${C4_STATUSLINE_EXPORT:-}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes) ;;
  *) exit 0 ;;
esac

if [ -n "$C4_CLAUDE_DIR" ]; then
  CLAUDE_BASE=$(echo "$C4_CLAUDE_DIR" | cut -d: -f1)
else
  CLAUDE_BASE="$HOME/.claude"
fi

SESSION_ID=$(echo "$input" | jq -r '.session_id // "__unknown__"')
CWD=$(echo "$input" | jq -r '.cwd // ""')

PROJECT_DIR_NAME=$(echo "$CWD" | sed 's|:|-|g; s|[/\\]|-|g')
LOG_DIR="$CLAUDE_BASE/statusline/$PROJECT_DIR_NAME"

{
  mkdir -p "$LOG_DIR"
  TS_MS=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
  LOG_ENTRY=$(printf '{"session_id":%s,"ts":%s,"data":%s}' \
    "$(echo "$SESSION_ID" | jq -Rs .)" \
    "$TS_MS" \
    "$input")
  echo "$LOG_ENTRY" >> "$LOG_DIR/$SESSION_ID.jsonl"
} 2>/dev/null || true