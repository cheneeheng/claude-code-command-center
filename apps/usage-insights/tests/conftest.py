"""Shared fixtures: a writable copy of the fixture Claude dir and a temp store."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import pytest

from usage_insights import reference

FIXTURE = Path(__file__).parent / "fixtures" / "claude"


@pytest.fixture(autouse=True)
def _no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    """Fail loudly when a test reaches the network or the ``claude`` CLI unstubbed.

    ``RuntimeError`` is not one of the failures ``reference.refresh`` absorbs.
    """

    def blocked(*_args: Any, **_kwargs: Any) -> Any:
        raise RuntimeError("network and subprocess are blocked in tests")

    monkeypatch.setattr(reference, "urlopen", blocked)
    monkeypatch.setattr(reference, "run", blocked)


def write_registry(claude_dir: Path, plugins: dict[str, list[dict[str, str]]]) -> None:
    """Write ``plugins/installed_plugins.json`` (install paths are absolute)."""
    registry = claude_dir / "plugins" / "installed_plugins.json"
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry.write_text(json.dumps({"version": 2, "plugins": plugins}), encoding="utf-8")


@pytest.fixture
def claude_dir(tmp_path: Path) -> Path:
    """A copy of the fixture Claude dir with ``fixplug`` installed at user scope."""
    dest = tmp_path / "claude"
    shutil.copytree(FIXTURE, dest)
    install = str(dest / "plugins" / "cache" / "fixplug")
    write_registry(
        dest, {"fixplug@market": [{"scope": "user", "installPath": install, "version": "1"}]}
    )
    return dest


@pytest.fixture
def db(tmp_path: Path) -> Path:
    return tmp_path / "home" / "usage.db"
