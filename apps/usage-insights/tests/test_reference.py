"""Reference data: fetched prices and built-in lists, cached with a fallback."""

from __future__ import annotations

import io
import json
import subprocess
import urllib.request
from datetime import UTC, timedelta
from pathlib import Path
from typing import Any

import pytest
from claude_usage import ModelPrice
from test_aggregate import EMPTY, NOW, StoreBuilder, _summary

from usage_insights import aggregate, cli, reference
from usage_insights.inventory import BUILTIN_TOOLS, load_inventory

TOOLS_MD = "## Tools\n\n| Tool | Description | Permission required |\n| :- | :- | :- |\n" + "".join(
    f"| `T{i}` | does {i} | No |\n" for i in range(12)
) + "\n| Rule | Tools |\n| :- | :- |\n| `Bash(npm *)` | Bash |\n"
LITELLM = {
    "claude-sonnet-5-5": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 2e-06,
        "output_cost_per_token": 1e-05,
    }
}
INIT_LINE = json.dumps(
    {
        "type": "control_response",
        "response": {
            "subtype": "success",
            "request_id": "ui",
            "response": {"agents": [{"name": "Explore"}, {"name": "Plan"}]},
        },
    }
)


class FakeNet:
    """Stands in for ``urlopen`` and ``subprocess.run`` inside ``reference``."""

    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.urls: list[str] = []
        self.runs: list[dict[str, Any]] = []

    def urlopen(self, req: urllib.request.Request, timeout: float) -> io.BytesIO:
        url = req.full_url
        self.urls.append(url)
        if self.fail:
            raise OSError("offline")
        body = json.dumps(LITELLM) if "litellm" in url else TOOLS_MD
        return io.BytesIO(body.encode())

    def run(self, args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
        self.runs.append({"args": args, **kwargs})
        if self.fail:
            raise subprocess.TimeoutExpired(args, 20)
        return subprocess.CompletedProcess(args, 0, '{"type":"system"}\n' + INIT_LINE, "")


@pytest.fixture
def net(monkeypatch: pytest.MonkeyPatch) -> FakeNet:
    fake = FakeNet()
    monkeypatch.setattr(reference, "urlopen", fake.urlopen)
    monkeypatch.setattr(reference, "run", fake.run)
    monkeypatch.setattr(reference.shutil, "which", lambda _name: "/bin/claude")
    return fake


def test_refresh_fetches_all_then_skips_fresh_parts(net: FakeNet, tmp_path: Path) -> None:
    lines: list[str] = []
    reference.refresh(tmp_path, NOW, lines.append)
    assert lines == ["fetched prices", "fetched tool list", "fetched agent list"]
    ref = reference.load(tmp_path)
    assert ref.prices["claude-sonnet-5-5"].input == 2.0
    assert ref.tools == [f"T{i}" for i in range(12)]
    assert ref.agents == ["Explore", "Plan"]
    assert ref.prices_fetched == NOW.isoformat()
    assert not (tmp_path / "reference.json.tmp").exists()

    lines.clear()
    reference.refresh(tmp_path, NOW + timedelta(hours=1), lines.append)
    assert lines == [] and len(net.urls) == 2  # nothing fetched again
    reference.refresh(tmp_path, NOW + timedelta(hours=25), lines.append)
    assert lines == ["fetched prices", "fetched tool list", "fetched agent list"]


def test_refresh_failure_keeps_previous(net: FakeNet, tmp_path: Path) -> None:
    reference.refresh(tmp_path, NOW, lambda _l: None)
    before = reference.load(tmp_path)
    net.fail = True
    lines: list[str] = []
    reference.refresh(tmp_path, NOW + timedelta(days=2), lines.append)
    assert len(lines) == 3 and all("failed" in line for line in lines)
    assert reference.load(tmp_path) == before


def test_tools_table_parse_and_minimum() -> None:
    assert reference.parse_tools(TOOLS_MD) == [f"T{i}" for i in range(12)]
    short = TOOLS_MD.replace("".join(f"| `T{i}` | does {i} | No |\n" for i in range(3, 12)), "")
    with pytest.raises(ValueError):
        reference.parse_tools(short)
    with pytest.raises(ValueError):
        reference.parse_tools("no table here")


def test_initialize_reads_agents(
    net: FakeNet, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-secret")
    monkeypatch.setenv("C4_USAGE_INSIGHTS_API_KEY", "sk-secret-2")
    assert reference.fetch_agents() == ["Explore", "Plan"]
    (call,) = net.runs
    assert call["args"][1:3] == ["-p", "--input-format"]
    assert "--no-session-persistence" in call["args"]
    assert json.loads(call["input"])["request"] == {"subtype": "initialize"}
    assert "ANTHROPIC_API_KEY" not in call["env"]
    assert "C4_USAGE_INSIGHTS_API_KEY" not in call["env"]
    assert call["timeout"] == reference.INIT_TIMEOUT_S

    monkeypatch.setattr(reference.shutil, "which", lambda _name: None)
    with pytest.raises(OSError):
        reference.fetch_agents()


def test_reference_load_unreadable_is_empty(tmp_path: Path) -> None:
    empty = reference.Reference({}, None, [], [])
    assert reference.load(tmp_path) == empty
    (tmp_path / "reference.json").write_text("{not json", encoding="utf-8")
    assert reference.load(tmp_path) == empty
    (tmp_path / "reference.json").write_text('{"prices": {"x": {"input": "a"}}}', encoding="utf-8")
    assert reference.load(tmp_path) == empty


def test_litellm_only_model_is_not_unpriced(db: Path) -> None:
    b = StoreBuilder(db)
    b.session("s1")
    b.message("s1", NOW - timedelta(days=1), 1_000_000, model="claude-new-9")
    out = _summary(db)
    assert out["totals"]["unpriced_models"] == ["claude-new-9"]
    assert out["totals"]["prices_as_of"] is None
    prices = {"claude-new-9": ModelPrice(7.0, 1, 1, 1, 1)}
    priced = aggregate.summary(
        db, EMPTY, "30d", NOW, [Path("/claude")], UTC,
        prices=prices, prices_as_of="2026-10-21T00:00:00+00:00",
    )
    assert priced["totals"]["unpriced_models"] == []
    assert priced["totals"]["cost_usd"] == pytest.approx(7.0)
    assert priced["totals"]["prices_as_of"] == "2026-10-21T00:00:00+00:00"


def test_inventory_uses_reference_lists_else_constants(claude_dir: Path) -> None:
    inv = load_inventory([claude_dir], [])
    assert inv.builtin_tools == list(BUILTIN_TOOLS)
    assert ("Explore", "built-in") in {(i.name, i.source) for i in inv.agents}
    inv = load_inventory([claude_dir], [], builtin_tools=["Zap"], builtin_agents=["helper-x", "Explore"]
    )
    assert inv.builtin_tools == ["Zap"]
    sources = {i.name: i.source for i in inv.agents}
    assert sources["helper-x"] == "built-in"
    assert "Plan" not in sources  # the fetched list replaces the hand-kept one
    assert sources["fixplug:helper"] == "plugin:fixplug"


def test_export_subcommand_refreshes_reference(
    net: FakeNet, claude_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(tmp_path / "home"))
    assert cli.main(["export", "--claude-dir", str(claude_dir)]) == 0
    assert reference.load(tmp_path / "home").tools
