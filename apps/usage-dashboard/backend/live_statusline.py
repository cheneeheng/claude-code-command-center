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


def _norm_ts(ts_raw: object) -> float | None:
    """Normalize a statusline timestamp to epoch seconds (logs may store ms or s)."""
    try:
        ts = float(ts_raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return ts / 1000.0 if ts > 1e12 else ts


def _record_pcts(rec: dict) -> tuple[float | None, float | None]:
    """Extract (five_hour_pct, seven_day_pct) from a statusline record."""
    rl = (rec.get("data") or {}).get("rate_limits") or {}
    fh = (rl.get("five_hour") or {}).get("used_percentage")
    sd = (rl.get("seven_day") or {}).get("used_percentage")
    return fh, sd


def read_history(hours: float, bucket_secs: int) -> dict:
    """Downsampled rate-limit % history over the last `hours`, ≤200 points/window.

    Walks every statusline line within the window and keeps the max pct per
    `bucket_secs` time bucket — a rate-limit % is monotone within its window, so
    the max is the honest sample. Returns ``{"five_hour": [[ts, pct]…],
    "seven_day": [[ts, pct]…]}`` sorted by ts (newest 200 kept)."""
    floor = time.time() - hours * 3600
    fh_buckets: dict[int, list[float]] = {}
    sd_buckets: dict[int, list[float]] = {}

    def keep(buckets: dict[int, list[float]], ts: float, pct: float) -> None:
        b = int(ts // bucket_secs)
        if b not in buckets or pct > buckets[b][1]:
            buckets[b] = [ts, pct]

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
                    ts = _norm_ts(rec.get("ts", 0))
                    if ts is None or ts < floor:
                        continue
                    fh, sd = _record_pcts(rec)
                    if fh is not None:
                        keep(fh_buckets, ts, fh)
                    if sd is not None:
                        keep(sd_buckets, ts, sd)
        except (OSError, PermissionError):
            continue

    def series(buckets: dict[int, list[float]]) -> list[list[float]]:
        return sorted(buckets.values(), key=lambda p: p[0])[-200:]

    return {"five_hour": series(fh_buckets), "seven_day": series(sd_buckets)}


def _forecast(samples: list[list[float]], now: float) -> float | None:
    """Epoch-seconds ETA to hit 100%, from the trailing hour's slope, or None.

    A two-point slope over the last hour is deliberately dumb — a rate-limit % is
    already a smoothed counter, so regression would be YAGNI. Returns None when
    flat/declining, already at the cap, or with fewer than two recent samples."""
    recent = [s for s in samples if s[0] >= now - 3600]
    if len(recent) < 2:
        return None
    (t0, p0), (t1, p1) = recent[0], recent[-1]
    dt, dp = t1 - t0, p1 - p0
    remaining = 100 - p1
    if dt <= 0 or dp <= 0 or remaining <= 0:
        return None
    return now + remaining / (dp / dt)


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
    result = {
        "available":    True,
        "five_hour":    top["five_hour"]    if top else None,
        "seven_day":    top["seven_day"]    if top else None,
        "model":        top["model"]        if top else None,
        "context_pct":  top["context_pct"]  if top else None,
        "session_cost": top["session_cost"] if top else None,
        "ts":           top["ts"]           if top else None,
        "sessions":     sessions_live,
    }

    # History + forecast are only meaningful when a live session reports limits;
    # skip the (second) file walk otherwise.
    if top is not None:
        fh_hist = read_history(hours=5, bucket_secs=90)["five_hour"]
        sd_hist = read_history(hours=168, bucket_secs=3600)["seven_day"]
        result["history"] = {"five_hour": fh_hist, "seven_day": sd_hist}
        result["forecast"] = {
            "five_hour_eta_ts": _forecast(fh_hist, now),
            "seven_day_eta_ts": _forecast(sd_hist, now),
        }
    return result
