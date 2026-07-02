"""Unit tests for the registry-reading / path public API (plugins.py)."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath, PureWindowsPath

import pytest

from claude_plugins import (
    claude_dir,
    load_installed_plugins,
    loose_bases,
    normalise_path,
    plugins_base,
)
from claude_plugins import plugins as plugins_mod


# ── claude_dir / plugins_base / loose_bases ─────────────────────────────────

def test_claude_dir_is_home_dot_claude() -> None:
    assert claude_dir() == Path.home() / ".claude"


def test_plugins_base_default_and_explicit(tmp_path: Path) -> None:
    assert plugins_base() == Path.home() / ".claude" / "plugins"
    assert plugins_base(tmp_path) == tmp_path / "plugins"


def test_loose_bases_default_and_explicit(tmp_path: Path) -> None:
    default = loose_bases(tmp_path)
    assert default == {
        "user": str(Path.home() / ".claude"),
        "project": str(tmp_path / ".claude"),
    }
    explicit = loose_bases(tmp_path, claude_dir=tmp_path / "cfg")
    assert explicit["user"] == str(tmp_path / "cfg")


# ── normalise_path ──────────────────────────────────────────────────────────

def test_normalise_path_empty_returns_empty() -> None:
    assert normalise_path("") == ""


def test_normalise_path_resolves_real_path(tmp_path: Path) -> None:
    # Path equality folds case on Windows, so this holds despite drive lowercasing.
    assert Path(normalise_path(str(tmp_path))) == tmp_path.resolve()


def test_normalise_path_posix_resolved_path_is_returned_verbatim(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A resolved path with no drive letter skips the Windows lowercasing branch,
    # exercised deterministically on any host OS.
    monkeypatch.setattr(
        plugins_mod.Path, "resolve", lambda self: PurePosixPath("/foo/bar")
    )
    assert normalise_path("whatever") == "/foo/bar"


def test_normalise_path_lowercases_windows_drive_letter(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Force a Windows-style resolved path so the drive-lowercasing branch runs
    # regardless of the host OS.
    monkeypatch.setattr(
        plugins_mod.Path, "resolve", lambda self: PureWindowsPath("C:/Users/x")
    )
    assert normalise_path("whatever") == "c:\\Users\\x"


def test_normalise_path_falls_back_on_oserror(monkeypatch: pytest.MonkeyPatch) -> None:
    def _boom(self: Path) -> Path:
        raise OSError("cannot resolve")

    monkeypatch.setattr(plugins_mod.Path, "resolve", _boom)
    assert normalise_path("some/path") == "some/path"


# ── load_installed_plugins ──────────────────────────────────────────────────

def _write_registry(claude_dir: Path, plugins: dict) -> None:
    base = claude_dir / "plugins"
    base.mkdir(parents=True, exist_ok=True)
    (base / "installed_plugins.json").write_text(
        json.dumps({"version": 1, "plugins": plugins}), encoding="utf-8"
    )


def test_load_installed_plugins_missing_registry_returns_empty_buckets(
    tmp_path: Path,
) -> None:
    assert load_installed_plugins(tmp_path, claude_dir=tmp_path) == {
        "local": [],
        "project": [],
        "user": [],
    }


def test_load_installed_plugins_malformed_registry_returns_empty_buckets(
    tmp_path: Path,
) -> None:
    base = tmp_path / "plugins"
    base.mkdir(parents=True)
    (base / "installed_plugins.json").write_text("{ not json", encoding="utf-8")
    assert load_installed_plugins(tmp_path, claude_dir=tmp_path)["user"] == []


def test_load_installed_plugins_buckets_by_scope_and_project(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    project.mkdir()
    _write_registry(
        tmp_path,
        {
            "user-plugin": [{"scope": "user", "version": "1.0", "installPath": "/u"}],
            "proj-plugin": [
                {"scope": "project", "projectPath": str(project), "installPath": "/p"}
            ],
            "other-proj-plugin": [
                {"scope": "local", "projectPath": str(tmp_path / "elsewhere")}
            ],
            "no-path-plugin": [{"scope": "local"}],  # local without projectPath -> skipped
            "bad-scope-plugin": [{"scope": "global"}],  # unknown scope -> skipped
        },
    )
    buckets = load_installed_plugins(project, claude_dir=tmp_path)
    assert [p["id"] for p in buckets["user"]] == ["user-plugin"]
    assert buckets["user"][0]["version"] == "1.0"
    assert [p["id"] for p in buckets["project"]] == ["proj-plugin"]
    assert buckets["local"] == []  # other-proj / no-path / bad-scope all excluded
