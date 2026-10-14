"""Shared fixtures: a writable copy of the fixture Claude dir and a temp store."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

FIXTURE = Path(__file__).parent / "fixtures" / "claude"


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
