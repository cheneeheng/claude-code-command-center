"""The typed query: validation, ranges, and agreement with the summary."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from test_aggregate import NOW, StoreBuilder, _summary

from usage_insights import query

DAY = timedelta(days=1)


def _run(db: Path, raw: dict[str, Any], now: datetime = NOW, **kw: Any) -> dict[str, Any]:
    return query.run(db, query.parse(raw, "30d"), now, UTC, **kw)


def _mixed_store(db: Path) -> StoreBuilder:
    b = StoreBuilder(db)
    b.session("a1", "C--w-alpha", "C:/w/alpha", "2026-10-01")
    b.session("a2", "C--w-alpha", "C:/w/alpha", "2026-09-01")
    b.session("b1", "C--w-beta", "C:/w/beta", "2026-10-01")
    for days_ago, sid, tokens, model in (
        (0, "a1", 1_000_000, "claude-opus-4-8"),
        (3, "a1", 500_000, "claude-sonnet-4-6"),
        (10, "b1", 2_000_000, "claude-opus-4-8"),
        (40, "a2", 3_000_000, "claude-haiku-4-5"),
        (50, "b1", 1_000_000, "claude-opus-4-8"),
        (100, "a2", 700_000, "claude-sonnet-4-6"),
    ):
        b.message(sid, NOW - days_ago * DAY, tokens, model)
    return b


def test_query_matches_summary(db: Path) -> None:
    _mixed_store(db)
    for range_key in ("7d", "30d", "90d", "all"):
        summary = _summary(db, range_key)
        for group_by, rows, key in (("project", "projects", "project"), ("model", "models", "model")):
            out = _run(db, {"metric": "cost_usd", "group_by": group_by, "range": range_key})
            got = {r["key"]: r["value"] for r in out["rows"]}
            want = {r[key]: r["cost_usd"] for r in summary[rows]}
            assert got == pytest.approx(want), (range_key, group_by)
        total = _run(db, {"metric": "cost_usd", "range": range_key})
        assert total["total"] == pytest.approx(summary["totals"]["cost_usd"])
        assert total["unit"] == "usd"


def test_query_compare_matches_summary_change(db: Path) -> None:
    _mixed_store(db)
    out = _run(db, {"metric": "cost_usd", "group_by": "project", "compare": "previous"})
    got = {r["key"]: r["change"] for r in out["rows"]}
    want = {r["project"]: r["change"] for r in _summary(db, "30d")["projects"]}
    assert got.keys() == want.keys()
    for k, change in want.items():
        assert got[k] == pytest.approx(change) if change is not None else got[k] is None


def test_query_month_range_and_previous_month(db: Path) -> None:
    now = datetime(2026, 10, 10, 12, 0, tzinfo=UTC)
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", datetime(2026, 10, 1, 1, tzinfo=UTC), 1)  # day 1: in
    b.message("s1", datetime(2026, 10, 10, 1, tzinfo=UTC), 2)  # day 10: in
    b.message("s1", datetime(2026, 9, 30, 23, tzinfo=UTC), 4)  # last month, day 30: out
    b.message("s1", datetime(2026, 9, 1, 1, tzinfo=UTC), 8)  # previous: day 1
    b.message("s1", datetime(2026, 9, 10, 23, tzinfo=UTC), 16)  # previous: day 10
    b.message("s1", datetime(2026, 9, 11, 1, tzinfo=UTC), 32)  # after the previous days
    out = _run(db, {"metric": "tokens", "range": "month", "compare": "previous"}, now)
    (row,) = out["rows"]
    assert (row["value"], row["previous"]) == (3, 24)
    assert row["change"] == pytest.approx(3 / 24 - 1)
    days = _run(db, {"metric": "tokens", "group_by": "day", "range": "month"}, now)["rows"]
    assert [r["key"] for r in days] == [f"2026-10-{d:02d}" for d in range(1, 11)]


def test_query_previous_month_is_clamped_to_its_length(db: Path) -> None:
    now = datetime(2026, 3, 31, 12, 0, tzinfo=UTC)
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", datetime(2026, 2, 28, 12, tzinfo=UTC), 5)
    out = _run(db, {"metric": "tokens", "range": "month", "compare": "previous"}, now)
    assert out["rows"][0]["previous"] == 5


@pytest.mark.parametrize(
    ("raw", "field"),
    [
        ({"metric": "dollars"}, "metric"),
        ({"metric": "interrupts", "group_by": "model"}, "group_by"),
        ({"metric": "cost_usd", "limit": 0}, "limit"),
        ({"metric": "cost_usd", "limit": True}, "limit"),
        ({"metric": "cost_usd", "filters": {"project": "alpha"}}, "filters.project"),
        ({"metric": "cost_usd", "filters": {"name": ["x"]}}, "filters.name"),
        ({"metric": "tool_calls", "filters": {"model": ["x"]}}, "filters.model"),
        ({"metric": "cost_usd", "range": "all", "compare": "previous"}, "compare"),
        ({"metric": "cost_usd", "group_by": "day", "compare": "previous"}, "compare"),
        ({"metric": "cost_usd", "compare": "yes"}, "compare"),
        ({"metric": "cost_usd", "range": "1y"}, "range"),
        ({"metric": "cost_usd", "colour": "red"}, "colour"),
        ({}, "metric"),
        (["cost_usd"], "query"),
    ],
)
def test_query_rejects_bad_specs(raw: Any, field: str) -> None:
    with pytest.raises(ValueError, match=field):
        query.parse(raw, "30d")


def test_query_defaults() -> None:
    spec = query.parse({"metric": "tokens"}, "7d")
    assert (spec.group_by, spec.range, spec.compare, spec.limit) == ("none", "7d", False, 12)


def test_query_day_series_is_never_cut(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", NOW - 2 * DAY, 10)
    rows = _run(db, {"metric": "tokens", "group_by": "day"})["rows"]
    assert len(rows) == 30
    assert rows[-1]["key"] == NOW.date().isoformat()
    assert rows[0]["key"] == (NOW.date() - 29 * DAY).isoformat()
    assert sum(r["value"] for r in rows) == 10 and rows[-3]["value"] == 10
    weeks = _run(db, {"metric": "tokens", "group_by": "week", "range": "90d"})["rows"]
    assert all(datetime.fromisoformat(r["key"]).weekday() == 0 for r in weeks)
    # 90d from Saturday Oct 3 starts Monday Jul 6: Mondays Jul 6 .. Sep 28.
    assert (weeks[0]["key"], weeks[-1]["key"], len(weeks)) == ("2026-07-06", "2026-09-28", 13)


def test_query_limit_keeps_top_rows(db: Path) -> None:
    _mixed_store(db)
    out = _run(db, {"metric": "tokens", "group_by": "model", "range": "all", "limit": 1})
    assert [r["key"] for r in out["rows"]] == ["claude-opus-4-8"]
    assert out["truncated"] is True
    assert out["total"] == 8_200_000


def test_query_sessions_total_is_distinct(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", NOW - DAY, 1)
    b.message("s1", NOW - 2 * DAY, 1)
    out = _run(db, {"metric": "sessions", "group_by": "day", "range": "7d"})
    assert sum(r["value"] for r in out["rows"]) == 2
    assert out["total"] == 1


def test_query_skill_uses_counts_typed_skill_once(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    t = NOW - DAY
    b.event("command", "typed", t)
    b.event("command", "clear", t)  # a built-in slash command, not a skill
    b.event("skill", "auto", t)
    b.event("tool", "Read", t)
    out = _run(db, {"metric": "skill_uses", "group_by": "skill"},
               skill_names=frozenset({"typed", "auto"}))
    assert {r["key"]: r["value"] for r in out["rows"]} == {"typed": 1, "auto": 1}
    named = _run(db, {"metric": "skill_uses", "filters": {"name": ["typed"]}},
                 skill_names=frozenset({"typed"}))
    assert named["total"] == 1


def test_query_model_filter_is_literal(db: Path) -> None:
    _mixed_store(db)
    assert _run(db, {"metric": "tokens", "filters": {"model": ["%"]}})["rows"][0]["value"] == 0
    opus = _run(db, {"metric": "tokens", "range": "all", "filters": {"model": ["claude-opus"]}})
    assert opus["total"] == 4_000_000


def test_query_project_filter_uses_labels(db: Path) -> None:
    _mixed_store(db)
    out = _run(db, {"metric": "tokens", "range": "all", "filters": {"project": ["beta"]}})
    assert out["total"] == 3_000_000


def test_query_session_label_is_title(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", NOW - DAY, 5)
    b.message("ghost", NOW - DAY, 3)  # no sessions row: the id stands in
    rows = _run(db, {"metric": "tokens", "group_by": "session"})["rows"]
    assert [(r["key"], r["label"]) for r in rows] == [("s1", "title s1"), ("ghost", "ghost")]


def test_query_missing_store_is_empty(tmp_path: Path) -> None:
    out = _run(tmp_path / "none.db", {"metric": "cost_usd", "group_by": "project"})
    assert (out["rows"], out["total"], out["truncated"]) == ([], 0, False)
