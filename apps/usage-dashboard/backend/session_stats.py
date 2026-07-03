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

import calendar
from collections import defaultdict
from dataclasses import asdict
from datetime import date, timedelta

import claude_usage

import dashboard_config

# Days of daily history shipped to the UI: 30 for the bar charts, 364 (52 weeks)
# for the activity heatmap.
CHART_DAYS = 30
HEATMAP_DAYS = 364


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
        "cache_savings_usd":      0.0,
        "cost_without_cache_usd": 0.0,
        "month_cost_usd":         0.0,
        "month_projected_usd":    0.0,
        "by_day":            [],
        "heatmap":           [],
        "by_project":        [],
        "by_model":          [],
    }


def _by_day(sessions: list[dict], days: int) -> list[dict]:
    """Tokens / cost / session count per calendar day, padded to the last `days` days."""
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
    span = [(today - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]
    return [{"date": d, **buckets.get(d, zero)} for d in span]


def _cache_economics(sessions: list[dict]) -> tuple[float, float]:
    """Estimated (cost_without_cache, savings) across all sessions.

    Without prompt caching, every cache-write and cache-read token would have
    been billed as a plain input token. Both figures use the pricing table
    (estimates), independent of any actual-cost overlay on live sessions."""
    with_cache = 0.0
    without_cache = 0.0
    for s in sessions:
        for m, tok in (s.get("per_model") or {}).items():
            costs = claude_usage.model_costs(m)
            if not costs:
                continue
            inp_c, out_c, cw_c, cr_c = costs
            with_cache += (
                tok["input"] * inp_c + tok["output"] * out_c
                + tok["cache_write"] * cw_c + tok["cache_read"] * cr_c
            ) / 1_000_000
            without_cache += (
                (tok["input"] + tok["cache_write"] + tok["cache_read"]) * inp_c
                + tok["output"] * out_c
            ) / 1_000_000
    return without_cache, without_cache - with_cache


def _month_costs(sessions: list[dict]) -> tuple[float, float]:
    """(month-to-date cost, linear projection to month end) for the current month."""
    today = date.today()
    prefix = today.isoformat()[:7]
    cost = sum(
        s["cost_usd"] for s in sessions if (s["last_ts"] or "").startswith(prefix)
    )
    days_in_month = calendar.monthrange(today.year, today.month)[1]
    return cost, cost / today.day * days_in_month


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
    cost_without_cache, cache_savings = _cache_economics(sessions)
    month_cost, month_projected = _month_costs(sessions)

    return {
        "total_sessions":    len(sessions),
        "total_input":       total_input,
        "total_output":      total_output,
        "total_cache_write": total_cache_write,
        "total_cache_read":  total_cache_read,
        "total_cost_usd":    sum(s["cost_usd"] for s in sessions),
        "total_tokens":      total_input + total_output + total_cache_write + total_cache_read,
        "cache_savings_usd":      cache_savings,
        "cost_without_cache_usd": cost_without_cache,
        "month_cost_usd":         month_cost,
        "month_projected_usd":    month_projected,
        "by_day":            _by_day(sessions, CHART_DAYS),
        "heatmap":           _by_day(sessions, HEATMAP_DAYS),
        "by_project":        _by_project(sessions),
        "by_model":          _by_model(sessions),
    }
