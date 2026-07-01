#!/usr/bin/env python3
"""Claude Code Statusline Hook (Python stdlib).

Drop-in replacement for statusline-hook.sh / statusline-hook.ps1. Reads the JSON blob
Claude Code pipes to stdin, prints a single colour-coded status line to stdout,
and appends the turn to a per-project / per-session JSONL log that the dashboard
server reads.

Works on Linux, macOS, and Windows (any terminal that supports ANSI escapes).
stdin and stdout are forced to UTF-8 so the piped JSON and the bar/arrow glyphs
survive on Windows consoles (the original port crashed here).

Setup (one-time):
    1. Copy this file to ~/.claude/statusline-hook.py
    2. Add to ~/.claude/settings.json:
         {
           "statusLine": {
             "type": "command",
             "command": "python3 ~/.claude/statusline-hook.py"
           }
         }
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Force UTF-8 so piped JSON decodes and the bar/arrow glyphs encode on Windows.
for _stream in (sys.stdin, sys.stdout):
    try:
        _stream.reconfigure(encoding="utf-8")  # type: ignore[union-attr]  # TextIOWrapper only
    except (AttributeError, ValueError):
        pass

# ── ANSI colours ───────────────────────────────────────────────────────────────

GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"

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
    pct = min(max(pct, 0), 100)
    filled = int(pct * width / 100)
    empty = width - filled
    return "▓" * filled + "░" * empty  # ▓░

def format_runtime(duration_ms: float) -> str:
    total_sec = int(duration_ms / 1000)
    hours = total_sec // 3600
    mins = (total_sec % 3600) // 60
    secs = total_sec % 60
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

def export_enabled() -> bool:
    """The JSONL export is opt-in via C4_STATUSLINE_EXPORT (1/true/yes)."""
    return os.environ.get("C4_STATUSLINE_EXPORT", "").strip().lower() in {"1", "true", "yes"}

def claude_base() -> Path:
    """Return the Claude config dir — the dir this hook is installed in."""
    return Path(__file__).resolve().parent

# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

    # --- Extract fields ---
    model = (data.get("model") or {}).get("id", "")
    duration_ms = (data.get("cost") or {}).get("total_duration_ms") or 0
    cost = (data.get("cost") or {}).get("total_cost_usd") or 0.0

    ctx = data.get("context_window") or {}
    raw_pct = int(ctx.get("used_percentage") or 0)
    # 1M-context models report a fifth of the real percentage; scale to match.
    pct = raw_pct * 5 if (ctx.get("context_window_size") or 0) == 1_000_000 else raw_pct

    rl = data.get("rate_limits") or {}
    fh_data = rl.get("five_hour") or {}
    sd_data = rl.get("seven_day") or {}

    rate_5h = int(fh_data.get("used_percentage") or 0)
    reset_5h = fh_data.get("resets_at") or 0
    rate_7d = int(sd_data.get("used_percentage") or 0)
    reset_7d = sd_data.get("resets_at") or 0

    # --- Format pieces ---
    runtime = format_runtime(duration_ms)
    cost_fmt = f"${cost:.4f}"
    bar = build_bar(pct)
    reset_5h_fmt = format_reset_time(reset_5h, include_day=False)
    reset_7d_fmt = format_reset_time(reset_7d, include_day=True)

    cc = ctx_color(pct)
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
        parts.append(f"{c5h}5H: {rate_5h}% (↺ {reset_5h_fmt}){RESET}")
    if sd_data.get("used_percentage") is not None:
        parts.append(f"{c7d}7D: {rate_7d}% (↺ {reset_7d_fmt}){RESET}")

    print(" | ".join(parts), flush=True)

    # --- Log to <claude>/statusline/<project>/<session_id>.jsonl (opt-in) ---
    if not export_enabled():
        return
    try:
        session_id = data.get("session_id") or "__unknown__"
        cwd = data.get("cwd") or ""
        # Encode cwd into the same dir-name format Claude Code uses.
        project_dir_name = cwd.replace(":", "-").replace("/", "-").replace("\\", "-")
        log_dir = claude_base() / "statusline" / project_dir_name
        log_dir.mkdir(parents=True, exist_ok=True)
        ts_ms = int(datetime.now(tz=timezone.utc).timestamp() * 1000)
        entry = {"session_id": session_id, "ts": ts_ms, "data": data}
        with (log_dir / f"{session_id}.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")
    except Exception:
        pass  # never let logging break the status line


if __name__ == "__main__":
    main()
