"""The typed query behind ``POST /api/query`` and the agent's ``run_query`` tool.

A spec names a metric, one grouping, filters, a range, and an optional
previous-period comparison. It is parsed once, here, into :class:`Spec`; a bad
spec is a ``ValueError`` naming the field. Every figure is computed from the
store with the same helpers as ``aggregate.summary``, so the two cannot disagree.
"""

from __future__ import annotations

import calendar
from collections import defaultdict
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import date, datetime, timedelta, tzinfo
from pathlib import Path
from typing import Any

from claude_usage import ModelPrice

from usage_insights import store
from usage_insights.aggregate import (
    Json,
    local_day,
    message_cost,
    project_labels,
    range_start,
    session_project,
)

_MESSAGE_GROUPS = ("none", "project", "model", "session", "day", "week")
GROUPINGS: dict[str, tuple[str, ...]] = {
    "cost_usd": _MESSAGE_GROUPS,
    "tokens": _MESSAGE_GROUPS,
    "sessions": _MESSAGE_GROUPS,
    "skill_uses": ("none", "skill", "project", "day", "week"),
    "agent_uses": ("none", "agent", "project", "day", "week"),
    "tool_calls": ("none", "tool", "project", "day", "week"),
    "interrupts": ("none", "project", "day", "week"),
}
# Event metrics and the store's event kinds they read. Values are SQL literals,
# never user input.
EVENT_KINDS: dict[str, tuple[str, ...]] = {
    "skill_uses": ("skill", "command"),
    "agent_uses": ("agent",),
    "tool_calls": ("tool",),
    "interrupts": ("interrupt",),
}
UNITS = {"cost_usd": "usd", "tokens": "tokens"}  # anything else counts
RANGE_DAYS: dict[str, int | None] = {"7d": 7, "30d": 30, "90d": 90, "month": None, "all": None}
FIELDS = ("metric", "group_by", "filters", "range", "compare", "limit")
DEFAULT_LIMIT = 12
MAX_LIMIT = 100
MAX_FILTER_VALUES = 50


@dataclass(frozen=True)
class Spec:
    """A validated query. Build it with :func:`parse`."""

    metric: str
    group_by: str
    range: str
    compare: bool
    limit: int
    projects: frozenset[str] = frozenset()
    models: tuple[str, ...] = ()
    names: tuple[str, ...] = ()


def _strings(value: Any, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise ValueError(f"{field} must be a list of strings")
    if len(value) > MAX_FILTER_VALUES:
        raise ValueError(f"{field} takes at most {MAX_FILTER_VALUES} values")
    return tuple(value)


def parse(raw: Any, default_range: str) -> Spec:
    """Validate a query spec.

    Args:
        raw: The decoded JSON spec.
        default_range: The range when the spec has none (the top bar's).

    Raises:
        ValueError: The spec is invalid; the message names the field.
    """
    if not isinstance(raw, dict):
        raise ValueError("query must be a JSON object")  # noqa: TRY004 - a 400, by contract
    for key in raw:
        if key not in FIELDS:
            raise ValueError(f"{key} is not a query field; fields are {', '.join(FIELDS)}")
    metric = raw.get("metric")
    if metric not in GROUPINGS:
        raise ValueError(f"metric must be one of {', '.join(GROUPINGS)}")
    group_by = raw.get("group_by", "none")
    if group_by not in GROUPINGS[metric]:
        raise ValueError(
            f"group_by for {metric} must be one of {', '.join(GROUPINGS[metric])}"
        )
    range_key = raw.get("range", default_range)
    if range_key not in RANGE_DAYS:
        raise ValueError(f"range must be one of {', '.join(RANGE_DAYS)}")
    compare = raw.get("compare")
    if compare not in (None, "previous"):
        raise ValueError('compare must be "previous" or left out')
    if compare and range_key == "all":
        raise ValueError("compare is not allowed with range all")
    if compare and group_by in ("day", "week"):
        raise ValueError("compare is not allowed with day or week groupings")
    limit = raw.get("limit", DEFAULT_LIMIT)
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= MAX_LIMIT:
        raise ValueError(f"limit must be a whole number from 1 to {MAX_LIMIT}")

    filters = raw.get("filters") or {}
    if not isinstance(filters, dict):
        raise ValueError("filters must be an object")  # noqa: TRY004 - a 400, by contract
    for key in filters:
        if key not in ("project", "model", "name"):
            raise ValueError(f"filters.{key} is not a filter; filters are project, model, name")
    events = metric in EVENT_KINDS
    if "model" in filters and events:
        raise ValueError("filters.model applies only to cost_usd, tokens, and sessions")
    if "name" in filters and not events:
        raise ValueError("filters.name applies only to skill, agent, tool, and interrupt metrics")
    return Spec(
        metric,
        group_by,
        range_key,
        compare is not None,
        limit,
        frozenset(_strings(filters["project"], "filters.project")) if "project" in filters
        else frozenset(),
        _strings(filters["model"], "filters.model") if "model" in filters else (),
        _strings(filters["name"], "filters.name") if "name" in filters else (),
    )


def _windows(range_key: str, today: date) -> tuple[date | None, date | None, date | None]:
    """``(start, prev_start, prev_end)``; the current window ends today."""
    if range_key == "month":
        first = today.replace(day=1)
        prev_first = (first - timedelta(days=1)).replace(day=1)
        last = calendar.monthrange(prev_first.year, prev_first.month)[1]
        return first, prev_first, prev_first.replace(day=min(today.day, last))
    days = RANGE_DAYS[range_key]
    start = range_start(today, days)
    if start is None or days is None:
        return None, None, None
    return start, start - timedelta(days=days), start - timedelta(days=1)


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _series_keys(group_by: str, first: date, today: date) -> Iterator[str]:
    step = timedelta(days=7 if group_by == "week" else 1)
    d = _monday(first) if group_by == "week" else first
    end = _monday(today) if group_by == "week" else today
    while d <= end:
        yield d.isoformat()
        d += step


def run(
    db: Path,
    spec: Spec,
    now: datetime,
    tz: tzinfo | None,
    prices: dict[str, ModelPrice] | None = None,
    skill_names: frozenset[str] = frozenset(),
) -> Json:
    """Run a query read-only against the store.

    Args:
        db: The store; a missing one gives empty rows.
        spec: From :func:`parse`.
        now: The aware current time; its local date is today.
        tz: The zone for local dates, as in ``aggregate.summary``.
        prices: The fetched price overlay.
        skill_names: Installed skills; a typed ``command`` counts as a skill use
            only when it names one.
    """
    today = now.date()
    start, prev_start, prev_end = _windows(spec.range, today)
    head: Json = {"metric": spec.metric, "group_by": spec.group_by, "range": spec.range,
                  "unit": UNITS.get(spec.metric, "count")}
    if not db.is_file():
        return {**head, "rows": [], "total": 0, "truncated": False}

    events = spec.metric in EVENT_KINDS
    with store.connect_read_only(db) as conn:
        sessions = {r[0]: r[1:] for r in conn.execute(
            "SELECT id, project, title, cwd, started, ended FROM sessions")}
        if events:
            kinds = EVENT_KINDS[spec.metric]
            sql = (f"SELECT kind, name, ts, session_id FROM events WHERE ts IS NOT NULL "
                   f"AND kind IN ({', '.join(repr(k) for k in kinds)})")
            params: list[str] = []
            if spec.names:
                sql += f" AND name IN ({', '.join('?' * len(spec.names))})"
                params += spec.names
        else:
            sql = ("SELECT session_id, model, ts, input, output, cache_write, cache_read, "
                   "cache_write_1h FROM messages WHERE ts IS NOT NULL")
            params = []
            if spec.models:
                # substr, not LIKE: % and _ in a filter are literal.
                sql += " AND (" + " OR ".join(
                    ["substr(model, 1, length(?)) = ?"] * len(spec.models)) + ")"
                for m in spec.models:
                    params += [m, m]
        rows = conn.execute(sql, params).fetchall()

    labels = project_labels(sessions)
    count_sessions = spec.metric == "sessions"
    cur: dict[str, float] = defaultdict(float)
    prev: dict[str, float] = defaultdict(float)
    cur_sids: dict[str, set[str]] = defaultdict(set)
    prev_sids: dict[str, set[str]] = defaultdict(set)
    all_sids: set[str] = set()
    total = 0.0
    first: date | None = None

    for row in rows:
        if events:
            kind, name, ts_raw, sid = row
            if kind == "command" and name not in skill_names:
                continue
            model, value = "", 1.0
        else:
            sid, model, ts_raw, inp, out, cw, cr, cw1h = row
            cost, tokens = message_cost(model, inp, out, cw, cr, cw1h, prices)
            name, value = "", cost if spec.metric == "cost_usd" else float(tokens)
        project = session_project(sid, sessions, labels)
        if spec.projects and project not in spec.projects:
            continue
        day = local_day(ts_raw, tz)
        if start is None or day >= start:
            period, sids = cur, cur_sids
            total += value
            all_sids.add(sid)
            first = day if first is None or day < first else first
        elif prev_start is not None and prev_end is not None and prev_start <= day <= prev_end:
            period, sids = prev, prev_sids
        else:
            continue
        g = spec.group_by
        if g == "model" and model == "unknown":
            continue  # as in the summary's model list
        key = {
            "none": "all", "project": project, "model": model, "session": sid,
            "day": day.isoformat(), "week": _monday(day).isoformat(),
        }.get(g, name)
        if count_sessions:
            sids[key].add(sid)
        else:
            period[key] += value

    if count_sessions:
        cur = {k: float(len(v)) for k, v in cur_sids.items()}
        prev = {k: float(len(v)) for k, v in prev_sids.items()}
        total = float(len(all_sids))

    series = spec.group_by in ("day", "week")
    if series:
        series_start = start or first
        keys = list(_series_keys(spec.group_by, series_start, today)) if series_start else []
    elif spec.group_by == "none":
        keys = ["all"]
    else:
        keys = sorted(cur, key=lambda k: (-cur[k], k))
    truncated = not series and len(keys) > spec.limit
    keys = keys if series else keys[: spec.limit]

    out_rows: list[Json] = []
    for key in keys:
        r: Json = {"key": key, "label": _label(spec.group_by, key, sessions),
                   "value": _num(cur.get(key, 0.0), spec.metric)}
        if spec.compare:
            p = prev.get(key, 0.0)
            r["previous"] = _num(p, spec.metric)
            r["change"] = (cur.get(key, 0.0) - p) / p if p else None
        out_rows.append(r)
    return {**head, "rows": out_rows, "total": _num(total, spec.metric),
            "truncated": truncated}


def _num(value: float, metric: str) -> float | int:
    """Counts and tokens are whole numbers; cost stays a float."""
    return value if metric == "cost_usd" else int(value)


def _label(group_by: str, key: str, sessions: dict[str, tuple[Any, ...]]) -> str:
    if group_by == "none":
        return "All"
    if group_by == "session" and key in sessions:
        return str(sessions[key][1] or key)
    return key
