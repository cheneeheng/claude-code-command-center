"""Historical usage stats from Claude Code session transcripts.

Parsing of `~/.claude/projects/**/*.jsonl` into per-session token/cost summaries
lives in the `claude-usage` library. This module adapts that into the dict shape
the rest of the dashboard consumes and adds the dashboard-specific aggregation
(totals + by-day / by-project / by-model breakdowns).

Cost is ESTIMATED (token counts x the library's pricing table), not the amount
Anthropic billed. For the authoritative per-session API cost of *currently live*
sessions, see live_statusline.py — merge.py overlays that on top of these estimates.

PUBLIC API
    load_sessions()           -> list of per-session dicts (newest first)
    summarize_sessions(rows)   -> aggregate stats (totals, by_day/project/model)
"""

from collections import defaultdict
from dataclasses import asdict
from datetime import date, timedelta

import claude_usage

import dashboard_config


def load_sessions() -> list[dict]:
    """Parse every transcript (via claude-usage) into per-session dicts, newest first."""
    return [asdict(s) for s in claude_usage.load_sessions(dashboard_config.CLAUDE_DIRS)]


# ── Aggregation ────────────────────────────────────────────────────────────────

def _empty_stats() -> dict:
    return {
        "total_sessions":    0,
        "total_tokens":      0,
        "total_input":       0,
        "total_output":      0,
        "total_cache_write": 0,
        "total_cache_read":  0,
        "total_cost_usd":    0.0,
        "by_day":            [],
        "by_project":        [],
        "by_model":          [],
    }


def _by_day(sessions: list[dict]) -> list[dict]:
    """Tokens / cost / session count per calendar day, padded to the last 30 days."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": 0})
    for s in sessions:
        if not s["last_ts"]:
            continue
        day = s["last_ts"][:10]
        buckets[day]["tokens"]   += s["total_tokens"]
        buckets[day]["cost"]     += s["cost_usd"]
        buckets[day]["sessions"] += 1

    today = date.today()
    zero = {"tokens": 0, "cost": 0.0, "sessions": 0}
    days = [(today - timedelta(days=i)).isoformat() for i in range(29, -1, -1)]
    return [{"date": d, **buckets.get(d, zero)} for d in days]


def _by_project(sessions: list[dict]) -> list[dict]:
    """Top 10 projects by token volume."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": 0})
    for s in sessions:
        p = s["project"] or "unknown"
        buckets[p]["tokens"]   += s["total_tokens"]
        buckets[p]["cost"]     += s["cost_usd"]
        buckets[p]["sessions"] += 1
    ranked = sorted(buckets.items(), key=lambda kv: kv[1]["tokens"], reverse=True)[:10]
    return [{"project": p, **v} for p, v in ranked]


def _by_model(sessions: list[dict]) -> list[dict]:
    """Tokens / estimated cost per raw model id (versions kept distinct)."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0})
    for s in sessions:
        for m, tok in (s.get("per_model") or {}).items():
            buckets[m]["tokens"] += tok["input"] + tok["output"] + tok["cache_write"] + tok["cache_read"]
            buckets[m]["cost"]   += claude_usage.estimated_cost({m: tok})
    ranked = sorted(
        ((m, v) for m, v in buckets.items() if m and v["tokens"] > 0),
        key=lambda kv: kv[1]["tokens"], reverse=True,
    )
    return [{"model": m, **v} for m, v in ranked]


def summarize_sessions(sessions: list[dict]) -> dict:
    """Aggregate per-session rows into the dashboard's summary stats block."""
    if not sessions:
        return _empty_stats()

    total_input       = sum(s["input_tokens"]       for s in sessions)
    total_output      = sum(s["output_tokens"]      for s in sessions)
    total_cache_write = sum(s["cache_write_tokens"] for s in sessions)
    total_cache_read  = sum(s["cache_read_tokens"]  for s in sessions)

    return {
        "total_sessions":    len(sessions),
        "total_input":       total_input,
        "total_output":      total_output,
        "total_cache_write": total_cache_write,
        "total_cache_read":  total_cache_read,
        "total_cost_usd":    sum(s["cost_usd"] for s in sessions),
        "total_tokens":      total_input + total_output + total_cache_write + total_cache_read,
        "by_day":            _by_day(sessions),
        "by_project":        _by_project(sessions),
        "by_model":          _by_model(sessions),
    }
