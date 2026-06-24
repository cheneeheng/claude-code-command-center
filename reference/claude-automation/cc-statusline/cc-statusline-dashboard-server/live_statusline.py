"""Live session state from the statusline hook's logs.

SOURCE
    ~/.claude/statusline/<project_name>/<session_id>.jsonl  (appended by the
    statusline hook on every prompt). The newest line per session carries the
    values Claude Code itself reported.

WHAT THIS MODULE PRODUCES
    Authoritative live values that cannot be derived from transcripts:
      - rate limits (5-hour and 7-day used %)
      - context-window used %
      - the ACTUAL API cost Anthropic reported (data.cost.total_cost_usd)
    Only sessions updated within `timeout` seconds are considered "live".

    This is the counterpart to session_stats.py: that module estimates cost from
    token counts, this one reports the real cost for active sessions. merge.py
    reconciles the two.

PUBLIC API
    read_statusline(timeout=None) -> dict (top-level rate limits + live sessions)
    trim_statusline_logs(max_lines=10_000) -> cap each log file's size
"""

import json
import time
from pathlib import Path

import dashboard_config

# Shape returned when there is nothing to report. `available` flips to True once
# any statusline file is readable, so the UI can distinguish "hook not set up"
# from "set up but no data yet".
_EMPTY = {
    "available": False,
    "five_hour": None, "seven_day": None,
    "model": None, "context_pct": None, "session_cost": None,
    "ts": None, "sessions": [],
}


def _statusline_files() -> list[Path]:
    """Every per-session statusline log across all configured CLAUDE_DIRS."""
    found: list[Path] = []
    for claude_dir in dashboard_config.CLAUDE_DIRS:
        statusline_dir = claude_dir / "statusline"
        if statusline_dir.exists():
            found.extend(statusline_dir.glob("*/*.jsonl"))
    return found


def trim_statusline_logs(max_lines: int = 10_000):
    """Keep only the most recent `max_lines` of each log to bound disk growth."""
    for fpath in _statusline_files():
        try:
            lines = fpath.read_text(encoding="utf-8").splitlines(keepends=True)
            if len(lines) > max_lines:
                fpath.write_text("".join(lines[-max_lines:]), encoding="utf-8")
        except (OSError, PermissionError):
            pass


def _latest_record_per_session() -> tuple[dict, bool]:
    """Walk every log and keep the newest record per session_id.

    Returns (by_session, any_readable). Each kept record gets a normalized
    `_ts` field in seconds (logs may store ms or s)."""
    by_session: dict[str, dict] = {}
    any_readable = False
    for fpath in _statusline_files():
        try:
            with open(fpath, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    any_readable = True
                    sid = (rec.get("session_id")
                           or (rec.get("data") or {}).get("session_id")
                           or "__unknown__")
                    ts_raw = rec.get("ts", 0)
                    ts = ts_raw / 1000.0 if ts_raw > 1e12 else float(ts_raw)  # ms vs s
                    if sid not in by_session or ts > by_session[sid].get("_ts", 0):
                        rec["_ts"] = ts
                        by_session[sid] = rec
        except (OSError, PermissionError):
            continue
    return by_session, any_readable


def _live_session(sid: str, rec: dict) -> dict:
    """Project one statusline record into the per-session shape the UI consumes."""
    data = rec.get("data") or {}
    rl = data.get("rate_limits") or {}
    fh = rl.get("five_hour") or {}
    sd = rl.get("seven_day") or {}
    return {
        "session_id":   sid[:8],
        "model":        (data.get("model") or {}).get("display_name"),
        "context_pct":  (data.get("context_window") or {}).get("used_percentage"),
        "session_cost": (data.get("cost") or {}).get("total_cost_usd"),  # actual API cost
        "five_hour":    {"used_pct": fh["used_percentage"], "resets_at": fh.get("resets_at")}
                        if fh.get("used_percentage") is not None else None,
        "seven_day":    {"used_pct": sd["used_percentage"], "resets_at": sd.get("resets_at")}
                        if sd.get("used_percentage") is not None else None,
        "ts":           rec.get("_ts"),  # seconds
    }


def read_statusline(timeout: int | None = None) -> dict:
    """Read all statusline logs and return current live state.

    With multiple concurrent sessions (or multiple CLAUDE_DIRS) each session's
    newest entry wins. Top-level rate limits come from the most recently active
    session that has them. Sessions idle longer than `timeout` seconds are
    dropped (default: dashboard_config.LIVE_SESSION_TIMEOUT_SECS)."""
    live_timeout = timeout if timeout is not None else dashboard_config.LIVE_SESSION_TIMEOUT_SECS

    if not _statusline_files():
        return dict(_EMPTY)

    by_session, any_readable = _latest_record_per_session()
    if not any_readable:
        return dict(_EMPTY)
    if not by_session:
        return {**_EMPTY, "available": True}

    # Most-recently-active first, dropping stale sessions.
    now = time.time()
    sessions_live = [
        _live_session(sid, rec)
        for sid, rec in sorted(by_session.items(),
                               key=lambda kv: kv[1].get("_ts", 0), reverse=True)
        if now - rec.get("_ts", 0) <= live_timeout
    ]

    # Top-level limits = newest live session that actually reports them.
    top = next((s for s in sessions_live if s["five_hour"]), None)
    return {
        "available":    True,
        "five_hour":    top["five_hour"]    if top else None,
        "seven_day":    top["seven_day"]    if top else None,
        "model":        top["model"]        if top else None,
        "context_pct":  top["context_pct"]  if top else None,
        "session_cost": top["session_cost"] if top else None,
        "ts":           top["ts"]           if top else None,
        "sessions":     sessions_live,
    }
