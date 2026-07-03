"""Historical usage stats from Claude Code session transcripts.

Parsing of `~/.claude/projects/**/*.jsonl` into per-session token/cost summaries
plus the per-message `Activity` rollups lives in the `claude-usage` library
(`load_usage`). This module adapts that into the dict shape the rest of the
dashboard consumes and adds the dashboard-specific aggregation: range/project
scoping, totals, trend deltas, plan value, outliers, the by-day / by-project /
by-model / model-mix / hour-of-week / tools breakdowns, and per-session derived
economics.

Cost is ESTIMATED (token counts x the library's pricing table), not the amount
Anthropic billed — and in v4 that estimate is canonical for every aggregate and
every session row (see merge.py: no actual-cost overlay).

PUBLIC API
    load_cached()                    -> (per-session dicts, Activity), memoized
    scope_sessions(rows, range, proj)-> the rows a request's cards/table cover
    summarize_sessions(rows, activity, range, project) -> aggregate stats block
"""

import calendar
import os
import threading
from collections import defaultdict
from dataclasses import asdict
from datetime import date, datetime, timedelta, timezone

import claude_usage

import dashboard_config

# Bar charts cap at 90 daily bars; the heatmap covers the full retained year.
CHART_DAYS = 90
HEATMAP_DAYS = 364

# Closed set of selectable ranges -> lookback days (None = all time).
RANGE_DAYS: dict[str, int | None] = {"7d": 7, "30d": 30, "90d": 90, "12m": 365, "all": None}

# ── Parse cache ──────────────────────────────────────────────────────────────
# Interactive range/project switching re-fetches /api/data per click; without a
# memo every click would re-parse every transcript. Key on a cheap os.stat sweep
# (file count + newest mtime) so edits invalidate it. Guarded because the
# threaded server may rebuild concurrently.
# less-code: single-process in-memory memo; upgrade path is per-file incremental
# parsing if the stat sweep itself ever becomes the cost.
_cache_lock = threading.Lock()
_cache_key: tuple[int, float] | None = None
_cache_val: tuple[list[dict], claude_usage.Activity] | None = None


def _cache_signature() -> tuple[int, float]:
    """A cheap (file_count, max_mtime) signature of the transcript set."""
    files = claude_usage.transcript_files(dashboard_config.CLAUDE_DIRS)
    max_mtime = 0.0
    for f in files:
        try:
            m = os.stat(f).st_mtime
        except OSError:
            continue
        if m > max_mtime:
            max_mtime = m
    return len(files), max_mtime


def load_cached() -> tuple[list[dict], claude_usage.Activity]:
    """Return (per-session dicts, Activity), reparsing only when transcripts change.

    Rows carry the derived per-session fields; they are treated as read-only by
    callers (payload output builds fresh dicts), so the cache is never mutated.
    """
    global _cache_key, _cache_val
    key = _cache_signature()
    with _cache_lock:
        if _cache_val is None or _cache_key != key:
            sessions, activity = claude_usage.load_usage(dashboard_config.CLAUDE_DIRS)
            rows = [asdict(s) for s in sessions]
            for s in rows:
                _add_derived(s)
            _cache_val = (rows, activity)
            _cache_key = key
        return _cache_val


# ── Per-session derived economics ────────────────────────────────────────────

def _add_derived(s: dict) -> None:
    """Attach duration / $-per-hour / cache-hit-% to one session row, in place."""
    first, last = _parse_ts(s.get("first_ts")), _parse_ts(s.get("last_ts"))
    duration = int((last - first).total_seconds()) if first and last else 0
    s["duration_secs"] = max(0, duration)
    # Sub-5-min sessions produce absurd hourly rates; suppress rather than mislead.
    s["cost_per_hour"] = (
        s["cost_usd"] / (s["duration_secs"] / 3600) if s["duration_secs"] >= 300 else None
    )
    cache_denom = s["input_tokens"] + s["cache_read_tokens"]
    s["cache_hit_pct"] = (
        s["cache_read_tokens"] / cache_denom * 100 if cache_denom > 0 else None
    )


# ── Time / range helpers ─────────────────────────────────────────────────────

def _parse_ts(ts: object) -> datetime | None:
    """Parse an ISO session timestamp into an aware datetime (naive -> UTC)."""
    if not isinstance(ts, str) or not ts:
        return None
    try:
        dt = datetime.fromisoformat(ts)
    except ValueError:
        return None
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


def _in_window(s: dict, lo: datetime | None, hi: datetime | None) -> bool:
    """Whether a session's ``last_ts`` falls in [lo, hi) (open bounds allowed)."""
    dt = _parse_ts(s.get("last_ts"))
    if dt is None:
        return False
    if lo is not None and dt < lo:
        return False
    if hi is not None and dt >= hi:
        return False
    return True


def _range_days(range_key: str) -> int | None:
    """Lookback days for a range key; unknown values fall back to 'all'."""
    return RANGE_DAYS.get(range_key, None)


def _project_scoped(rows: list[dict], project: str | None) -> list[dict]:
    """Rows for one project (exact match), or all rows when project is unset."""
    if not project:
        return rows
    return [s for s in rows if s.get("project") == project]


def scope_sessions(rows: list[dict], range_key: str, project: str | None) -> list[dict]:
    """The sessions a request's cards and table cover: project then range filtered."""
    proj = _project_scoped(rows, project)
    days = _range_days(range_key)
    if days is None:
        return proj
    cutoff = datetime.now().astimezone() - timedelta(days=days)
    return [s for s in proj if _in_window(s, cutoff, None)]


# ── Aggregation ──────────────────────────────────────────────────────────────

def _cache_economics(sessions: list[dict]) -> tuple[float, float]:
    """Estimated (cost_without_cache, savings) across the given sessions.

    Without prompt caching, every cache-write and cache-read token would have
    been billed as a plain input token. Both figures use the pricing table."""
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
    """(month-to-date cost, linear projection to month end) for the current month.

    A billing-cycle figure: always the calendar month, ignoring range and project."""
    today = date.today()
    prefix = today.isoformat()[:7]
    cost = sum(
        s["cost_usd"] for s in sessions if (s["last_ts"] or "").startswith(prefix)
    )
    days_in_month = calendar.monthrange(today.year, today.month)[1]
    return cost, cost / today.day * days_in_month


def _by_project(sessions: list[dict]) -> list[dict]:
    """Top 10 projects by token volume (cost carried alongside)."""
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


def _strip(s: dict) -> dict:
    """A session row without the internal ``per_model`` aggregation detail."""
    return {k: v for k, v in s.items() if k != "per_model"}


def _delta(cur: list[dict], prev: list[dict]) -> dict:
    """Percentage change of tokens / cost / sessions vs the preceding window.

    Each metric is None when its previous value is 0 (no baseline to divide by)."""
    def pct(c: float, p: float) -> float | None:
        return None if p == 0 else (c - p) / p * 100
    cur_tok = sum(s["total_tokens"] for s in cur)
    prev_tok = sum(s["total_tokens"] for s in prev)
    cur_cost = sum(s["cost_usd"] for s in cur)
    prev_cost = sum(s["cost_usd"] for s in prev)
    return {
        "tokens_pct":   pct(cur_tok, prev_tok),
        "cost_pct":     pct(cur_cost, prev_cost),
        "sessions_pct": pct(len(cur), len(prev)),
    }


def _daybucket(b: claude_usage.DayBucket) -> dict:
    """A DayBucket as the {date, tokens, cost, sessions} shape the charts expect."""
    return {"date": b.date, "tokens": b.tokens, "cost": b.cost, "sessions": b.sessions}


def summarize_sessions(
    sessions: list[dict],
    activity: claude_usage.Activity,
    range_key: str = "all",
    project: str | None = None,
) -> dict:
    """Aggregate per-session rows into the dashboard's summary stats block.

    ``sessions`` is the full (all-project, all-time) row set; scoping to the
    request's range/project happens here so deltas can also see the preceding
    window. Time-series come from ``activity`` (project-agnostic — see the
    accepted limitation below)."""
    days = _range_days(range_key)
    proj_rows = _project_scoped(sessions, project)

    if days is None:
        cur = proj_rows
        delta = None
    else:
        now = datetime.now().astimezone()
        cur_cutoff = now - timedelta(days=days)
        prev_cutoff = now - timedelta(days=days * 2)
        cur = [s for s in proj_rows if _in_window(s, cur_cutoff, None)]
        prev = [s for s in proj_rows if _in_window(s, prev_cutoff, cur_cutoff)]
        delta = _delta(cur, prev)

    cost_without_cache, cache_savings = _cache_economics(cur)
    # Month cost/plan ignore range and project: a billing-cycle figure over everything.
    month_cost, month_projected = _month_costs(sessions)
    price = dashboard_config.PLAN_PRICE_USD
    plan = None if price is None else {
        "price_usd": price,
        "month_value_usd": month_cost,
        "ratio": month_cost / price,
    }

    top_sessions = sorted(cur, key=lambda s: s["cost_usd"], reverse=True)[:5]

    # Time-series: project-scoping is NOT applied (Activity is not project-bucketed).
    # Accepted, documented limitation — cards/tables are scoped, these show all
    # projects when a project filter is active. Upgrade path: per-project DayBucket.
    span = min(days or CHART_DAYS, CHART_DAYS)
    daily = activity.daily[-span:]

    return {
        "total_sessions":    len(cur),
        "total_input":       sum(s["input_tokens"]       for s in cur),
        "total_output":      sum(s["output_tokens"]      for s in cur),
        "total_cache_write": sum(s["cache_write_tokens"] for s in cur),
        "total_cache_read":  sum(s["cache_read_tokens"]  for s in cur),
        "total_cost_usd":    sum(s["cost_usd"]           for s in cur),
        "total_tokens":      sum(s["total_tokens"]       for s in cur),
        "cache_savings_usd":      cache_savings,
        "cost_without_cache_usd": cost_without_cache,
        "month_cost_usd":         month_cost,
        "month_projected_usd":    month_projected,
        "delta":             delta,
        "plan":              plan,
        "by_day":            [_daybucket(b) for b in daily],
        "heatmap":           [_daybucket(b) for b in activity.daily],
        "model_mix":         [{"date": b.date, "per_family": b.per_family} for b in daily],
        "hour_dow":          activity.hour_dow,
        "tools":             [{"name": n, "count": c} for n, c in
                              sorted(activity.tools.items(), key=lambda kv: kv[1], reverse=True)[:15]],
        "by_project":        _by_project(cur),
        "by_model":          _by_model(cur),
        "top_sessions":      [_strip(s) for s in top_sessions],
    }
