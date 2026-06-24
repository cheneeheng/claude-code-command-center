#!/usr/bin/env python3

##############################################################
# 26.05.04: ERROR - ISSUE WITH PIPE, THIS SCRIPT DOESNT WORK #
##############################################################
"""
Claude Code Statusline Hook (Python stdlib)
--------------------------------------------
Drop-in replacement for statusline.sh / statusline.ps1.
Reads the JSON blob Claude Code pipes to stdin, then prints a single
colour-coded status line to stdout.

Works on Linux, macOS, and Windows (any terminal that supports ANSI escapes).

Setup (one-time):
    1. Copy this file to ~/.claude/statusline.py
    2. Add to ~/.claude/settings.json:
         {
           "hooks": {
             "StatusLine": [
               {
                 "type": "command",
                 "command": "python3 ~/.claude/statusline.py"
               }
             ]
           }
         }
"""

import sys
import json
import os
from datetime import datetime, timezone
from pathlib import Path

# ── ANSI colours ───────────────────────────────────────────────────────────────

GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
RESET  = "\033[0m"

# ── Helpers ────────────────────────────────────────────────────────────────────

def ctx_color(pct: int) -> str:
    if pct < 30:
        return GREEN
    if pct < 50:
        return YELLOW
    return RED

def rate_color(pct: int) -> str:
    if pct < 30:
        return GREEN
    if pct < 70:
        return YELLOW
    return RED

def build_bar(pct: int, width: int = 10) -> str:
    filled = int(pct * width / 100)
    empty  = width - filled
    return "\u2593" * filled + "\u2591" * empty  # ▓░

def format_runtime(duration_ms: float) -> str:
    total_sec = int(duration_ms / 1000)
    hours = total_sec // 3600
    mins  = (total_sec % 3600) // 60
    secs  = total_sec % 60
    if hours > 0:
        return f"{hours}h {mins}m {secs}s"
    return f"{mins}m {secs}s"

def format_reset_time(unix_ts: float, include_day: bool = False) -> str:
    if not unix_ts:
        return "---" if include_day else "--:--"
    try:
        dt = datetime.fromtimestamp(unix_ts, tz=timezone.utc).astimezone()
        if include_day:
            return dt.strftime("%a %H:%M")
        return dt.strftime("%H:%M")
    except (OSError, OverflowError, ValueError):
        return "---" if include_day else "--:--"

# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    try:
        data = json.loads(sys.stdin.read())
    except json.JSONDecodeError:
        return

    # --- Extract fields ---
    model       = (data.get("model") or {}).get("id", "")
    duration_ms = (data.get("cost") or {}).get("total_duration_ms") or 0
    cost        = (data.get("cost") or {}).get("total_cost_usd") or 0.0
    pct         = int((data.get("context_window") or {}).get("used_percentage") or 0)

    rl      = data.get("rate_limits") or {}
    fh_data = rl.get("five_hour") or {}
    sd_data = rl.get("seven_day")  or {}

    rate_5h  = int(fh_data.get("used_percentage") or 0)
    reset_5h = fh_data.get("resets_at") or 0
    rate_7d  = int(sd_data.get("used_percentage") or 0)
    reset_7d = sd_data.get("resets_at") or 0

    # --- Format pieces ---
    runtime     = format_runtime(duration_ms)
    cost_fmt    = f"${cost:.4f}"
    bar         = build_bar(pct)
    reset_5h_fmt = format_reset_time(reset_5h, include_day=False)
    reset_7d_fmt = format_reset_time(reset_7d, include_day=True)

    cc  = ctx_color(pct)
    c5h = rate_color(rate_5h)
    c7d = rate_color(rate_7d)

    # --- Assemble line ---
    parts = [
        model,
        f"{cc}{bar} {pct}%{RESET}",
        runtime,
        cost_fmt,
    ]

    # Rate limits are only present for Pro/Max subscribers
    if fh_data.get("used_percentage") is not None:
        parts.append(f"{c5h}5H: {rate_5h}% (\u21ba {reset_5h_fmt}){RESET}")
    if sd_data.get("used_percentage") is not None:
        parts.append(f"{c7d}7D: {rate_7d}% (\u21ba {reset_7d_fmt}){RESET}")

    print(" | ".join(parts), flush=True)

    # --- Log to ~/.claude/statusline/<YYYY-MM>.jsonl ---
    try:
        log_dir = Path.home() / ".claude" / "statusline"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / (datetime.now().strftime("%Y-%m") + ".jsonl")
        entry = {"logged_at": datetime.now(tz=timezone.utc).isoformat(), **data}
        with log_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")
    except Exception:
        pass  # never let logging break the status line


if __name__ == "__main__":
    main()