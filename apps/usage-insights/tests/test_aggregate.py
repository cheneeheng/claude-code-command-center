"""Aggregation: totals, range scoping, projection, health, inventory."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone, tzinfo
from pathlib import Path

import pytest
from conftest import write_registry

from usage_insights import aggregate, export, store
from usage_insights.inventory import Inventory, Item, load_inventory

NOW = datetime(2026, 10, 3, 12, 0, tzinfo=UTC)  # a Saturday
EMPTY = Inventory(skills=[], agents=[], mcp_servers=[], builtin_tools=[])


class StoreBuilder:
    """Write sessions, messages, and events straight into a fresh store."""

    def __init__(self, db: Path) -> None:
        db.parent.mkdir(parents=True, exist_ok=True)
        self.db = db
        self.conn = store.connect(db)
        store.ensure_schema(self.conn)
        self.n = 0

    def session(self, sid: str, project: str = "p", cwd: str | None = None, ended: str = "") -> None:
        self.conn.execute(
            "INSERT INTO sessions (id, project, title, cwd, ended) VALUES (?, ?, ?, ?, ?)",
            (sid, project, f"title {sid}", cwd, ended),
        )

    def message(self, sid: str, ts: datetime, input_tokens: int, model: str = "claude-opus-4-8") -> None:
        self.n += 1
        self.conn.execute(
            "INSERT INTO messages VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0)",
            (f"k{self.n}", sid, model, ts.isoformat(), input_tokens),
        )

    def event(self, kind: str, name: str, ts: datetime, sid: str = "s1") -> None:
        self.n += 1
        self.conn.execute(
            "INSERT INTO events VALUES (?, ?, ?, ?, ?)",
            (f"{kind}:{self.n}", kind, name, ts.isoformat(), sid),
        )


def _summary(db: Path, range_key: str = "30d", inventory: Inventory = EMPTY, now: datetime = NOW) -> dict:
    return aggregate.summary(db, inventory, range_key, now, [Path("/claude")], now.tzinfo)


class _DstEnd(tzinfo):
    """UTC+2 until 2026-10-25 01:00 UTC, UTC+1 after: Europe's DST end, no tzdata needed."""

    CUT = datetime(2026, 10, 25, 1, 0)

    def fromutc(self, dt: datetime) -> datetime:
        return dt + timedelta(hours=2 if dt.replace(tzinfo=None) < self.CUT else 1)

    def utcoffset(self, dt: datetime | None) -> timedelta:
        return timedelta(hours=2 if dt is None or dt.replace(tzinfo=None) < self.CUT else 1)

    def dst(self, dt: datetime | None) -> timedelta:
        return timedelta(0)


# ── totals and spend ────────────────────────────────────────────────────────


def test_summary_totals_match_hand_computed_fixture(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    out = _summary(db, "7d")
    # m1 opus-4-8 100/50, 400 5m + 600 1h writes; m2 opus 10/5; m3 haiku-4-5 7/3;
    # m4 sonnet-4-6 20/10. Prices per 1M tokens.
    cost = (100 * 5 + 50 * 25 + 400 * 6.25 + 600 * 10 + 10 * 5 + 5 * 25) / 1e6
    cost += (7 * 1 + 3 * 5) / 1e6 + (20 * 3 + 10 * 15) / 1e6
    assert out["totals"]["tokens"] == {
        "input": 137, "output": 68, "cache_write": 1000, "cache_read": 0, "total": 1205,
    }
    assert out["totals"]["cost_usd"] == pytest.approx(cost)
    assert out["totals"]["sessions"] == 2
    assert out["totals"]["unpriced_models"] == []
    assert [p["project"] for p in out["projects"]] == ["alpha", "beta"]
    assert out["models"][0]["model"] == "claude-opus-4-8"
    assert [s["title"] for s in out["sessions"]] == ["Alpha work", "Beta prompt"]
    assert out["last_export"] is not None
    assert len(out["projection"]["pace"]) == 30
    assert out["projection"]["pace"][-1]["date"] == "2026-10-03"


def test_range_scoping_and_previous_period_change(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", NOW - timedelta(days=8), 1_000_000)  # previous 7d window
    b.message("s1", NOW - timedelta(days=1), 2_000_000)  # current 7d window
    b.message("s1", NOW - timedelta(days=20), 9_000_000)  # outside both
    out = _summary(db, "7d")
    assert out["totals"]["tokens"]["total"] == 2_000_000
    (project,) = out["projects"]
    assert project["change"] == pytest.approx(1.0)
    assert project["share"] == pytest.approx(1.0)
    assert _summary(db, "all")["projects"][0]["change"] is None
    # 7d starts at today minus 6 days: a message exactly 6 days back is in.
    b.message("s1", NOW - timedelta(days=6), 1)
    assert _summary(db, "7d")["totals"]["tokens"]["total"] == 2_000_001
    with pytest.raises(ValueError):
        _summary(db, "12m")


def test_project_label_from_cwd_with_collision(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1", "C--a-repo", "/a/repo", "2026-10-01")
    b.session("s2", "C--b-repo", "/b/repo", "2026-10-01")
    b.session("s3", "C--nocwd", None, "2026-10-01")
    for sid in ("s1", "s2", "s3"):
        b.message(sid, NOW - timedelta(days=1), 10)
    labels = sorted(p["project"] for p in _summary(db)["projects"])
    assert labels == ["C--nocwd", "repo (C--a-repo)", "repo (C--b-repo)"]


def test_project_label_prefers_the_launch_folder(db: Path) -> None:
    b = StoreBuilder(db)
    # The folder name encodes where sessions start; a later session wandered into
    # a subfolder, which must not rename the project.
    b.session("s1", "C--w-mono", "C:/w/mono", "2026-10-01")
    b.session("s2", "C--w-mono", "C:/w/mono/apps/sub", "2026-10-02")
    b.message("s1", NOW - timedelta(days=1), 10)
    assert [p["project"] for p in _summary(db)["projects"]] == ["mono"]


def test_used_mcp_server_not_configured_shows_unknown(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    for tool in ("mcp__claude-in-chrome__navigate", "mcp__claude-in-chrome__computer", "Read"):
        b.event("tool", tool, NOW - timedelta(days=1))
    inv = Inventory([], [], [Item("github", "user")], [])
    assert _summary(db, "7d", inv)["tools"]["mcp_servers"] == [
        {"name": "github", "source": "user", "calls": 0},
        {"name": "claude-in-chrome", "source": "unknown", "calls": 2},
    ]


# ── projection ──────────────────────────────────────────────────────────────


def test_local_dates_follow_the_zone_rules_of_each_timestamp(db: Path) -> None:
    # The server's "now" carries today's fixed offset (UTC+1, after DST ended), but a
    # message from before the change must use that day's offset (UTC+2).
    now = datetime(2026, 10, 28, 12, 0, tzinfo=timezone(timedelta(hours=1)))
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", datetime(2026, 10, 20, 22, 30, tzinfo=UTC), 1000)  # 00:30 on the 21st
    out = aggregate.summary(db, EMPTY, "30d", now, [Path("/claude")], _DstEnd())
    pace = {d["date"]: d["tokens"] for d in out["projection"]["pace"]}
    assert (pace["2026-10-20"], pace["2026-10-21"]) == (0, 1000)


def test_projection_forecast_and_band(db: Path) -> None:
    now = datetime(2026, 10, 14, 18, 0, tzinfo=UTC)  # a Wednesday, 3/4 of the day gone
    b = StoreBuilder(db)
    b.session("s1")
    for days_ago in range(1, 15):  # 14 complete days at $5 and 1M tokens each
        b.message("s1", now - timedelta(days=days_ago), 1_000_000)
    b.message("s1", now.replace(hour=10), 1_000_000)  # today
    proj = _summary(db, now=now)["projection"]
    week, month = proj["week"]["cost_usd"], proj["month"]["cost_usd"]
    # Week: Mon + Tue + today = $15, remaining = 0.25 + 4 days.
    assert week["actual"] == pytest.approx(15.0)
    assert week["forecast"] == pytest.approx(15.0 + 5 * 4.25)
    assert week["low"] == pytest.approx(week["forecast"])
    # Month: Oct 1..14 = $70, remaining = 0.25 + 17 days.
    assert month["actual"] == pytest.approx(70.0)
    assert month["forecast"] == pytest.approx(70.0 + 5 * 17.25)
    assert proj["week"]["tokens"]["forecast"] == pytest.approx(3e6 + 1e6 * 4.25)
    assert proj["by_project"][0]["week_cost_forecast"] == pytest.approx(week["forecast"])

    for days_ago in (2, 4, 6, 8):  # four heavy days widen the band
        b.message("s1", now - timedelta(days=days_ago), 2_000_000)
    week = _summary(db, now=now)["projection"]["week"]["cost_usd"]
    assert week["low"] < week["forecast"] < week["high"]

    b.message("s1", now - timedelta(days=5), 50_000_000)  # one outlier day
    week = _summary(db, now=now)["projection"]["week"]["cost_usd"]
    # The band always contains the forecast, even when the mean leaves the quartiles.
    assert week["low"] <= week["forecast"] <= week["high"]


# ── health ──────────────────────────────────────────────────────────────────


def _skills(names: list[str]) -> Inventory:
    return Inventory([Item(n, "user") for n in names], [], [], [])


def test_skill_status_each_rule(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    day = timedelta(days=1)
    for i in range(3):  # troubled: every recent use is followed by an interrupt
        b.event("skill", "troubled", NOW - (i + 1) * day, "s-t")
        b.event("interrupt", "", NOW - (i + 1) * day + timedelta(minutes=5), "s-t")
    b.event("skill", "declining", NOW - 2 * day)
    for i in range(4):
        b.event("skill", "declining", NOW - (35 + i) * day)
    b.event("skill", "lately", NOW - 45 * day)
    for i in range(3):  # tool errors right after every use: normal work, not trouble
        b.event("skill", "healthy", NOW - (i + 1) * day, "s-h")
        b.event("tool_error", "Bash", NOW - (i + 1) * day + timedelta(minutes=2), "s-h")
    names = ["healthy", "lately", "declining", "troubled", "never"]
    rows = _summary(db, "all", _skills(names))["skills"]
    assert [(r["name"], r["status"]) for r in rows] == [
        ("never", "never_used"),
        ("troubled", "troubled"),
        ("declining", "declining"),
        ("lately", "unused_lately"),
        ("healthy", "healthy"),
    ]
    by_name = {r["name"]: r for r in rows}
    assert by_name["troubled"]["trouble_rate"] == pytest.approx(1.0)
    assert by_name["healthy"]["trouble_rate"] == 0.0
    assert by_name["declining"]["trend"] == [4, 1]
    assert by_name["never"]["last_used"] is None
    assert by_name["lately"]["last_used"].startswith("2026-08-19")


def test_typed_vs_auto_invocation(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    t = NOW - timedelta(days=1)
    b.event("command", "typed", t)
    b.event("command", "both", t)
    b.event("skill", "both", t)
    b.event("skill", "auto", t)
    b.event("skill", "builtin-skill", t)  # used but not installed
    rows = {r["name"]: r for r in _summary(db, "7d", _skills(["typed", "both", "auto"]))["skills"]}
    assert {n: r["invoked"] for n, r in rows.items()} == {
        "typed": "typed", "both": "both", "auto": "auto", "builtin-skill": "auto",
    }
    assert rows["both"]["uses"] == 2
    assert rows["builtin-skill"]["source"] == "unknown"


def test_slash_builtin_not_counted_as_skill(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.event("command", "clear", NOW - timedelta(days=1))
    assert _summary(db, "7d", _skills(["x"]))["skills"] == [
        {
            "name": "x", "source": "user", "status": "never_used", "uses": 0,
            "last_used": None, "trend": [0, 0], "trouble_rate": 0.0, "invoked": None,
        }
    ]


# ── inventory ───────────────────────────────────────────────────────────────


def test_unused_builtin_tools_and_mcp_servers(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    inv = load_inventory([claude_dir], [Path("/work/beta")])
    assert {(i.name, i.source) for i in inv.mcp_servers} == {
        ("github", "user"), ("beta-db", "project"), ("fix-server", "plugin:fixplug"),
    }
    tools = _summary(db, "7d", inv)["tools"]
    assert {t["name"] for t in tools["used"]} >= {"Read", "Grep", "mcp__github__create_issue"}
    assert "Bash" in tools["unused_builtin"]
    assert "Read" not in tools["unused_builtin"]
    calls = {m["name"]: m["calls"] for m in tools["mcp_servers"]}
    assert calls == {"github": 1, "beta-db": 0, "fix-server": 0}
    skills = {r["name"]: r for r in _summary(db, "7d", inv)["skills"]}
    assert skills["fixplug:unused-skill"]["status"] == "never_used"
    assert skills["my-skill"]["source"] == "user"
    assert skills["my-skill"]["invoked"] == "both"
    agents = {r["name"]: r["source"] for r in _summary(db, "7d", inv)["agents"]}
    assert agents["Explore"] == "built-in"
    assert agents["fixplug:helper"] == "plugin:fixplug"


def test_plugin_inventory_spans_projects(claude_dir: Path, tmp_path: Path) -> None:
    proj_a, proj_b = tmp_path / "proj-a", tmp_path / "proj-b"
    for proj, skill in ((proj_a, "a-skill"), (proj_b, "b-skill")):
        plugin = tmp_path / "plugins" / skill / "skills" / skill
        plugin.mkdir(parents=True)
        (plugin / "SKILL.md").write_text(f"---\nname: {skill}\n---\n", encoding="utf-8")
    loose = proj_a / ".claude" / "skills" / "loose"
    loose.mkdir(parents=True)
    (loose / "SKILL.md").write_text("---\nname: loose\n---\n", encoding="utf-8")
    fix = str(claude_dir / "plugins" / "cache" / "fixplug")
    write_registry(
        claude_dir,
        {
            "fixplug@market": [
                {"scope": "user", "installPath": fix},
                {"scope": "project", "projectPath": str(proj_a), "installPath": fix},
            ],
            "pa@m": [{"scope": "local", "projectPath": str(proj_a),
                      "installPath": str(tmp_path / "plugins" / "a-skill")}],
            "pb@m": [{"scope": "project", "projectPath": str(proj_b),
                      "installPath": str(tmp_path / "plugins" / "b-skill")}],
        },
    )
    inv = load_inventory([claude_dir], [proj_a, proj_b])
    names = [i.name for i in inv.skills]
    assert {"pa:a-skill", "pb:b-skill", "fixplug:unused-skill", "loose", "my-skill"} <= set(names)
    assert names.count("fixplug:unused-skill") == 1
