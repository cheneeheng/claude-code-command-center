"""Turn the store into the ``/api/summary`` payload.

Every number is computed here, server-side; the frontend only renders it.
"""

from __future__ import annotations

import calendar
import re
import statistics
from bisect import bisect_right
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, tzinfo
from pathlib import Path, PurePath
from typing import Any

from claude_usage import estimated_cost, price_for

from usage_insights import store
from usage_insights.inventory import Inventory, Item

RANGES: dict[str, int | None] = {"7d": 7, "30d": 30, "90d": 90, "all": None}
PACE_DAYS = 14  # complete days behind the forecast rate
PACE_STRIP_DAYS = 30
TOP_SESSIONS = 100
HEALTH_WINDOW_DAYS = 30
TROUBLE_MIN_USES = 3
# Measured 2026-10-14 on local data: an interrupt follows 4.5% of all tool calls
# within 15 min, so 0.2 is about 4x the baseline. Tool errors follow 39.8% of all
# tool calls, which makes them noise here, so they do not count as trouble.
TROUBLE_RATE = 0.2
TROUBLE_WINDOW_MIN = 15
DECLINE_MIN_USES = 4
STATUS_ORDER = ("never_used", "troubled", "declining", "unused_lately", "healthy")
TROUBLE_KINDS = ("interrupt",)

Json = dict[str, Any]


def _period(actual: float, rate: float, low: float, high: float, remaining: float) -> Json:
    return {
        "actual": actual,
        "forecast": actual + rate * remaining,
        "low": actual + low * remaining,
        "high": actual + high * remaining,
    }


def _projection(daily: dict[date, float], now: datetime) -> dict[str, Json]:
    """Week and month so far plus forecast for one daily series.

    The rate is the mean of the last :data:`PACE_DAYS` complete days. The band
    uses their quartiles, widened to always contain the forecast.
    """
    today = now.date()
    series = [daily.get(today - timedelta(days=i), 0.0) for i in range(1, PACE_DAYS + 1)]
    mean = statistics.fmean(series)
    q1, _, q3 = statistics.quantiles(series, n=4, method="inclusive")
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    rest_of_today = 1 - (now - midnight).total_seconds() / 86400
    week_start = today - timedelta(days=today.weekday())
    month_start = today.replace(day=1)
    month_end = today.replace(day=calendar.monthrange(today.year, today.month)[1])
    out = {}
    for key, start, end in (
        ("week", week_start, week_start + timedelta(days=6)),
        ("month", month_start, month_end),
    ):
        actual = sum(v for d, v in daily.items() if start <= d <= today)
        remaining = rest_of_today + (end - today).days
        out[key] = _period(actual, mean, min(q1, mean), max(q3, mean), remaining)
    return out


def _labels(sessions: dict[str, tuple[Any, ...]]) -> dict[str, str]:
    """Project folder -> display label: basename of the folder sessions start in.

    Claude Code names the project folder after the launch dir, with every
    non-alphanumeric replaced by ``-``. A ``cwd`` that encodes to the folder name
    is that dir; otherwise the latest ``cwd`` stands in.
    """
    latest: dict[str, tuple[str, str]] = {}
    for project, _title, cwd, _started, ended in sessions.values():
        if not cwd:
            continue
        launch = re.sub(r"[^A-Za-z0-9]", "-", cwd) == project
        rank = ("1" if launch else "0") + (ended or "")
        if project not in latest or rank > latest[project][0]:
            latest[project] = (rank, cwd)
    base = {p: PurePath(cwd).name or cwd for p, (_, cwd) in latest.items()}
    counts = Counter(base.values())
    labels = {p: (f"{b} ({p})" if counts[b] > 1 else b) for p, b in base.items()}
    for project, *_ in sessions.values():
        labels.setdefault(project, project)
    return labels


def _norm(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "_", name)


def _health(
    items: list[Item],
    uses: dict[str, list[tuple[datetime, str, str]]],
    trouble: dict[str, list[datetime]],
    in_range: Any,
    now: datetime,
) -> list[Json]:
    """Rows of the skill or subagent health table, worst status first."""
    sources = {i.name: i.source for i in items}
    recent_start = now - timedelta(days=HEALTH_WINDOW_DAYS)
    prior_start = recent_start - timedelta(days=HEALTH_WINDOW_DAYS)
    window = timedelta(minutes=TROUBLE_WINDOW_MIN)
    rows: list[Json] = []
    for name in sorted(set(sources) | set(uses)):
        all_uses = uses.get(name, [])
        recent = [u for u in all_uses if u[0] >= recent_start]
        prior = [u for u in all_uses if prior_start <= u[0] < recent_start]
        troubled = 0
        for ts, sid, _mode in recent:
            marks = trouble.get(sid, [])
            i = bisect_right(marks, ts)
            if i < len(marks) and marks[i] <= ts + window:
                troubled += 1
        rate = troubled / len(recent) if recent else 0.0
        last = max((u[0] for u in all_uses), default=None)
        if not all_uses:
            status = "never_used"
        elif len(recent) >= TROUBLE_MIN_USES and rate >= TROUBLE_RATE:
            status = "troubled"
        elif len(prior) >= DECLINE_MIN_USES and len(recent) < len(prior) / 2:
            status = "declining"
        elif last is not None and last < recent_start:
            status = "unused_lately"
        else:
            status = "healthy"
        modes = {u[2] for u in all_uses}
        rows.append(
            {
                "name": name,
                "source": sources.get(name, "unknown"),
                "status": status,
                "uses": sum(1 for u in all_uses if in_range(u[0])),
                "last_used": last.isoformat() if last else None,
                "trend": [len(prior), len(recent)],
                "trouble_rate": rate,
                "invoked": "both" if len(modes) > 1 else next(iter(modes), None),
            }
        )
    rows.sort(key=lambda r: (STATUS_ORDER.index(r["status"]), -r["uses"], r["name"]))
    return rows


def _empty() -> Json:
    zero = {"actual": 0.0, "forecast": 0.0, "low": 0.0, "high": 0.0}
    period = {"tokens": zero, "cost_usd": zero}
    return {
        "last_export": None,
        "totals": {
            "cost_usd": 0.0,
            "tokens": dict.fromkeys(
                ("input", "output", "cache_write", "cache_read", "total"), 0
            ),
            "sessions": 0,
            "unpriced_models": [],
        },
        "projection": {"week": period, "month": period, "by_project": [], "pace": []},
        "projects": [],
        "models": [],
        "sessions": [],
        "skills": [],
        "agents": [],
        "tools": {"used": [], "unused_builtin": [], "mcp_servers": []},
    }


def summary(
    db: Path,
    inventory: Inventory,
    range_key: str,
    now: datetime,
    data_dirs: list[Path],
    tz: tzinfo | None,
) -> Json:
    """Build the ``/api/summary`` payload.

    Messages and events without a timestamp are left out of every figure.

    Args:
        db: The store file. A missing store gives the empty payload.
        inventory: What is installed.
        range_key: One of :data:`RANGES`.
        now: The aware current time; its date is today.
        data_dirs: The Claude dirs searched, echoed for the empty state.
        tz: The zone that turns timestamps into local dates. ``None`` is the
            system zone, applied with the rules in force at each timestamp, so
            dates before a DST change keep that day's offset.

    Raises:
        ValueError: ``range_key`` is not a known range.
    """
    if range_key not in RANGES:
        raise ValueError(f"range must be one of {', '.join(RANGES)}")
    payload: Json = {
        "range": range_key,
        "generated_at": now.isoformat(),
        "data_dirs": [str(d) for d in data_dirs],
        "store_path": str(db),
    }
    if not db.is_file():
        return {**payload, **_empty()}

    with store.connect_read_only(db) as conn:
        sessions = {r[0]: r[1:] for r in conn.execute(
            "SELECT id, project, title, cwd, started, ended FROM sessions")}
        messages = conn.execute(
            "SELECT session_id, model, ts, input, output, cache_write, cache_read, "
            "cache_write_1h FROM messages WHERE ts IS NOT NULL").fetchall()
        events = conn.execute(
            "SELECT kind, name, ts, session_id FROM events WHERE ts IS NOT NULL").fetchall()
        last = conn.execute("SELECT value FROM meta WHERE key = 'last_export'").fetchone()

    today = now.date()
    days = RANGES[range_key]
    start = today - timedelta(days=days - 1) if days else None
    prev_start = start - timedelta(days=days) if start and days else None

    def in_range(ts: datetime) -> bool:
        return start is None or ts.astimezone(tz).date() >= start

    labels = _labels(sessions)

    def label(sid: str) -> str:
        return labels.get(sessions[sid][0], sid) if sid in sessions else sid

    tokens: Counter[str] = Counter()
    cost_total = 0.0
    range_sessions: set[str] = set()
    unpriced: set[str] = set()
    projects: dict[str, Json] = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": set()})
    prev_cost: dict[str, float] = defaultdict(float)
    models: dict[str, Json] = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": set()})
    per_session: dict[str, Json] = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "models": set()})
    daily_tokens: dict[date, float] = defaultdict(float)
    daily_cost: dict[date, float] = defaultdict(float)
    project_daily: dict[str, dict[date, float]] = defaultdict(lambda: defaultdict(float))

    for sid, model, ts_raw, inp, out, cw, cr, cw1h in messages:
        day = datetime.fromisoformat(ts_raw).astimezone(tz).date()
        counts = {"input": inp, "output": out, "cache_write": cw, "cache_read": cr,
                  "cache_write_1h": cw1h}
        total = inp + out + cw + cr + cw1h
        cost = estimated_cost({model: counts})
        proj = label(sid)
        daily_tokens[day] += total
        daily_cost[day] += cost
        project_daily[proj][day] += cost
        if prev_start is not None and start is not None and prev_start <= day < start:
            prev_cost[proj] += cost
        if start is not None and day < start:
            continue
        tokens.update({"input": inp, "output": out, "cache_write": cw + cw1h,
                       "cache_read": cr, "total": total})
        cost_total += cost
        range_sessions.add(sid)
        if model != "unknown" and price_for(model) is None:
            unpriced.add(model)
        for bucket in (projects[proj], models[model]):
            bucket["tokens"] += total
            bucket["cost"] += cost
            bucket["sessions"].add(sid)
        row = per_session[sid]
        row["tokens"] += total
        row["cost"] += cost
        row["models"].add(model)

    # Events: tools, skills, subagents, trouble markers.
    tool_calls: Counter[str] = Counter()
    skill_names = {i.name for i in inventory.skills}
    skill_uses: dict[str, list[tuple[datetime, str, str]]] = defaultdict(list)
    agent_uses: dict[str, list[tuple[datetime, str, str]]] = defaultdict(list)
    trouble: dict[str, list[datetime]] = defaultdict(list)
    for kind, name, ts_raw, sid in events:
        ts = datetime.fromisoformat(ts_raw)
        if kind == "tool" and in_range(ts):
            tool_calls[name] += 1
        elif kind == "skill":
            skill_uses[name].append((ts, sid, "auto"))
        elif kind == "command" and name in skill_names:
            skill_uses[name].append((ts, sid, "typed"))
        elif kind == "agent":
            agent_uses[name].append((ts, sid, "auto"))
        elif kind in TROUBLE_KINDS:
            trouble[sid].append(ts)
    for marks in trouble.values():
        marks.sort()

    pace_days = [today - timedelta(days=i) for i in range(PACE_STRIP_DAYS - 1, -1, -1)]
    by_project = []
    for proj, series in project_daily.items():
        forecast = _projection(series, now)
        if forecast["month"]["forecast"] > 0:
            by_project.append({
                "project": proj,
                "week_cost_forecast": forecast["week"]["forecast"],
                "month_cost_forecast": forecast["month"]["forecast"],
            })
    by_project.sort(key=lambda p: -p["month_cost_forecast"])
    token_proj, cost_proj = _projection(daily_tokens, now), _projection(daily_cost, now)

    top = sorted(per_session.items(), key=lambda kv: -kv[1]["tokens"])[:TOP_SESSIONS]
    return {
        **payload,
        "last_export": last[0] if last else None,
        "totals": {
            "cost_usd": cost_total,
            "tokens": {k: tokens[k] for k in
                       ("input", "output", "cache_write", "cache_read", "total")},
            "sessions": len(range_sessions),
            "unpriced_models": sorted(unpriced),
        },
        "projection": {
            "week": {"tokens": token_proj["week"], "cost_usd": cost_proj["week"]},
            "month": {"tokens": token_proj["month"], "cost_usd": cost_proj["month"]},
            "by_project": by_project,
            "pace": [{"date": d.isoformat(), "tokens": daily_tokens.get(d, 0),
                      "cost_usd": daily_cost.get(d, 0.0)} for d in pace_days],
        },
        "projects": sorted(
            (
                {
                    "project": p,
                    "tokens": v["tokens"],
                    "cost_usd": v["cost"],
                    "share": v["cost"] / cost_total if cost_total else 0.0,
                    "change": (v["cost"] - prev_cost[p]) / prev_cost[p]
                    if days and prev_cost[p] > 0 else None,
                    "sessions": len(v["sessions"]),
                }
                for p, v in projects.items()
            ),
            key=lambda r: -r["cost_usd"],
        ),
        "models": sorted(
            ({"model": m, "tokens": v["tokens"], "cost_usd": v["cost"],
              "sessions": len(v["sessions"])} for m, v in models.items() if m != "unknown"),
            key=lambda r: -r["cost_usd"],
        ),
        "sessions": [
            {
                "id": sid,
                "title": sessions[sid][1] or sid if sid in sessions else sid,
                "project": label(sid),
                "started": sessions[sid][3] if sid in sessions else None,
                "ended": sessions[sid][4] if sid in sessions else None,
                "tokens": v["tokens"],
                "cost_usd": v["cost"],
                "models": sorted(v["models"]),
            }
            for sid, v in top
        ],
        "skills": _health(inventory.skills, skill_uses, trouble, in_range, now),
        "agents": _health(inventory.agents, agent_uses, trouble, in_range, now),
        "tools": {
            "used": [{"name": n, "calls": c} for n, c in tool_calls.most_common()],
            "unused_builtin": [t for t in inventory.builtin_tools if t not in tool_calls],
            "mcp_servers": _mcp_servers(inventory.mcp_servers, tool_calls),
        },
    }


def _mcp_servers(servers: list[Item], tool_calls: Counter[str]) -> list[Json]:
    """Configured MCP servers with their calls, then used ones not configured.

    Tool names are ``mcp__<server>__<tool>``; Claude Code keeps or replaces
    punctuation in ``<server>`` depending on the server, so both sides are
    compared with non-alphanumerics mapped to ``_``.
    """
    used: Counter[str] = Counter()
    shown: dict[str, str] = {}
    for name, calls in tool_calls.items():
        parts = name.split("__")
        if name.startswith("mcp__") and len(parts) >= 3:
            used[_norm(parts[1])] += calls
            shown.setdefault(_norm(parts[1]), parts[1])
    rows = [{"name": s.name, "source": s.source, "calls": used.pop(_norm(s.name), 0)}
            for s in servers]
    rows += [{"name": shown[k], "source": "unknown", "calls": c} for k, c in used.most_common()]
    return rows
