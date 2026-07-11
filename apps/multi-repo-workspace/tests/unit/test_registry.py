"""registry: cascade, search paths, init, doctor, state home, atomic writes."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from roundtable import registry


def test_search_paths_order(monkeypatch, tmp_path):
    monkeypatch.setenv("C4_ROUNDTABLE_REGISTRY", str(tmp_path / "env.json"))
    paths = registry.registry_search_paths("explicit.json")
    assert paths[0].endswith("explicit.json")
    assert paths[1].endswith("env.json")
    assert paths[2].endswith(".roundtable.json")
    assert ".config" in paths[3]


def test_search_paths_no_env():
    assert len(registry.registry_search_paths()) == 2


def test_load_registry_missing_returns_empty(tmp_path):
    cfg = registry.load_registry(str(tmp_path / "nope.json"))
    assert cfg.port == registry.DEFAULT_PORT
    assert cfg.projects == []


def test_load_registry_env_var(monkeypatch, registry_file):
    monkeypatch.setenv("C4_ROUNDTABLE_REGISTRY", registry_file)
    cfg = registry.load_registry()
    assert [p.name for p in cfg.projects] == ["repo"]


def _write(tmp_path: Path, data) -> str:
    reg = tmp_path / "reg.json"
    reg.write_text(json.dumps(data), encoding="utf-8")
    return str(reg)


def test_load_registry_bad_shape(tmp_path):
    with pytest.raises(ValueError, match="expected top-level shape"):
        registry.load_registry(_write(tmp_path, {"projects": "nope"}))


def test_load_registry_missing_name(tmp_path, project):
    with pytest.raises(ValueError, match="missing 'name'"):
        registry.load_registry(_write(tmp_path, {"projects": [{"path": project.path}]}))


def test_load_registry_duplicate_name(tmp_path, project):
    entry = {"name": "x", "path": project.path}
    with pytest.raises(ValueError, match="duplicate project name"):
        registry.load_registry(_write(tmp_path, {"projects": [entry, dict(entry)]}))


def test_load_registry_missing_path(tmp_path):
    with pytest.raises(ValueError, match="missing 'path'"):
        registry.load_registry(_write(tmp_path, {"projects": [{"name": "x"}]}))


def test_load_registry_bad_path(tmp_path):
    data = {"projects": [{"name": "x", "path": str(tmp_path / "missing")}]}
    with pytest.raises(ValueError, match="not a directory"):
        registry.load_registry(_write(tmp_path, data))


def test_cascade_defaults_then_project(tmp_path, project):
    data = {
        "port": 9000,
        "defaults": {"model": "claude-opus-4-8", "max_turns": 5},
        "projects": [
            {"name": "a", "path": project.path},
            {"name": "b", "path": project.path, "model": "claude-haiku-4-5"},
        ],
    }
    cfg = registry.load_registry(_write(tmp_path, data))
    assert cfg.port == 9000
    a, b = cfg.projects
    assert a.model == "claude-opus-4-8" and a.max_turns == 5
    assert b.model == "claude-haiku-4-5" and b.max_turns == 5
    # untouched knobs fall through to code defaults
    assert a.planning_template == registry.DEFAULT_PLANNING_TEMPLATE
    assert a.planning_permission_mode == "acceptEdits"


def test_state_home_default_and_override(monkeypatch, tmp_path):
    monkeypatch.delenv("C4_ROUNDTABLE_HOME", raising=False)
    assert registry.state_home() == Path.home() / ".roundtable"
    monkeypatch.setenv("C4_ROUNDTABLE_HOME", str(tmp_path / "custom"))
    assert registry.state_home() == tmp_path / "custom"


def test_atomic_write_text_preserves_newlines(tmp_path):
    target = tmp_path / "sub" / "f.txt"
    registry.atomic_write_text(target, "a\nb\r\nc")
    assert target.read_bytes() == b"a\nb\r\nc"


def test_atomic_write_retries_permission_error(tmp_path, monkeypatch):
    target = tmp_path / "f.json"
    real_replace = os.replace
    calls = {"n": 0}

    def flaky(src, dst):
        calls["n"] += 1
        if calls["n"] < 3:
            raise PermissionError("locked")
        return real_replace(src, dst)

    monkeypatch.setattr(registry.os, "replace", flaky)
    monkeypatch.setattr(registry.time, "sleep", lambda s: None)
    registry.atomic_write_json(target, {"ok": True})
    assert json.loads(target.read_text(encoding="utf-8")) == {"ok": True}


def test_atomic_write_persistent_permission_error(tmp_path, monkeypatch):
    def always(src, dst):
        raise PermissionError("locked hard")

    monkeypatch.setattr(registry.os, "replace", always)
    monkeypatch.setattr(registry.time, "sleep", lambda s: None)
    with pytest.raises(PermissionError):
        registry.atomic_write_text(tmp_path / "f.txt", "x")


# --- init ------------------------------------------------------------------------


def _mkrepo(root: Path, name: str) -> Path:
    repo = root / name
    (repo / ".git").mkdir(parents=True)
    (repo / registry.DEFAULT_PLANNING_DIR).mkdir(parents=True)
    return repo


def test_discover_repos_and_dedupe(tmp_path):
    _mkrepo(tmp_path / "a", "proj")
    _mkrepo(tmp_path / "b", "proj")
    repo_no_planning = tmp_path / "c" / "bare"
    (repo_no_planning / ".git").mkdir(parents=True)
    found = registry.discover_repos(str(tmp_path))
    names = [f["name"] for f in found]
    assert names == ["proj", "proj-2"]


def test_suffix_increments():
    assert registry._suffix("foo") == "foo-2"
    assert registry._suffix("foo-2") == "foo-3"


def test_cmd_init_fresh_and_no_clobber(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _mkrepo(tmp_path, "proj")
    out = registry.cmd_init(scan=str(tmp_path))
    assert "wrote" in out and "1 project(s)" in out
    data = json.loads((tmp_path / ".roundtable.json").read_text(encoding="utf-8"))
    assert data["projects"][0]["name"] == "proj"
    assert data["defaults"]["planning_template"] == registry.DEFAULT_PLANNING_TEMPLATE
    with pytest.raises(FileExistsError):
        registry.cmd_init(scan=str(tmp_path))
    assert "wrote" in registry.cmd_init(scan=str(tmp_path), force=True)


def test_cmd_init_dry_run(tmp_path, capsys, monkeypatch):
    monkeypatch.chdir(tmp_path)
    out = registry.cmd_init(dry_run=True)
    assert "would write" in out
    assert '"projects"' in capsys.readouterr().out
    assert not (tmp_path / ".roundtable.json").exists()


def test_cmd_init_merge(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _mkrepo(tmp_path, "one")
    registry.cmd_init(scan=str(tmp_path))
    _mkrepo(tmp_path, "two")
    out = registry.cmd_init(scan=str(tmp_path), merge=True)
    assert "added 1 new project(s)" in out
    data = json.loads((tmp_path / ".roundtable.json").read_text(encoding="utf-8"))
    assert [p["name"] for p in data["projects"]] == ["one", "two"]
    # a second merge adds nothing
    assert "added 0" in registry.cmd_init(scan=str(tmp_path), merge=True)


def test_cmd_init_merge_name_collision(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _mkrepo(tmp_path / "x", "proj")
    registry.cmd_init(scan=str(tmp_path / "x"))
    _mkrepo(tmp_path / "y", "proj")
    registry.cmd_init(scan=str(tmp_path), merge=True)
    data = json.loads((tmp_path / ".roundtable.json").read_text(encoding="utf-8"))
    assert sorted(p["name"] for p in data["projects"]) == ["proj", "proj-2"]


def test_cmd_init_merge_missing_target(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    with pytest.raises(FileNotFoundError):
        registry.cmd_init(merge=True)


# --- doctor ----------------------------------------------------------------------


def test_doctor_ok(registry_file, project, capsys, claude_on_path):
    assert registry.cmd_doctor(registry_file) == 0
    out = capsys.readouterr().out
    assert "0 error(s)" in out


def test_doctor_load_error(tmp_path, capsys):
    bad = tmp_path / "bad.json"
    bad.write_text("{", encoding="utf-8")
    with pytest.raises(json.JSONDecodeError):
        registry.load_registry(str(bad))
    data = {"projects": [{"name": "x", "path": str(tmp_path / "gone")}]}
    reg = tmp_path / "reg.json"
    reg.write_text(json.dumps(data), encoding="utf-8")
    assert registry.cmd_doctor(str(reg)) == 1
    assert "error:" in capsys.readouterr().out


def test_doctor_findings(tmp_path, project, capsys, claude_on_path, monkeypatch):
    data = {
        "projects": [
            {
                "name": "x",
                "path": project.path,
                "permission_mode": "yolo",
                "allowed_tools": [],
            }
        ]
    }
    reg = tmp_path / "reg.json"
    reg.write_text(json.dumps(data), encoding="utf-8")
    assert registry.cmd_doctor(str(reg)) == 1
    out = capsys.readouterr().out
    assert "unknown permission_mode" in out
    assert "allowed_tools is empty" in out


def test_doctor_no_projects_and_missing_bins(tmp_path, capsys, monkeypatch):
    reg = tmp_path / "reg.json"
    reg.write_text(json.dumps({"projects": []}), encoding="utf-8")
    monkeypatch.setattr(registry.shutil, "which", lambda b: None)
    assert registry.cmd_doctor(str(reg)) == 1  # git missing is an error
    out = capsys.readouterr().out
    assert "no projects configured" in out
    assert "git not found" in out


def test_doctor_claude_bin_missing(tmp_path, project, capsys, monkeypatch):
    reg = tmp_path / "reg.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "x", "path": project.path}]}),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        registry.shutil, "which", lambda b: "/usr/bin/git" if b == "git" else None
    )
    assert registry.cmd_doctor(str(reg)) == 1
    assert "claude_bin" in capsys.readouterr().out


def test_doctor_planning_dir_warning(tmp_path, capsys, claude_on_path):
    bare = tmp_path / "bare"
    bare.mkdir()
    reg = tmp_path / "reg.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "x", "path": str(bare)}]}), encoding="utf-8"
    )
    assert registry.cmd_doctor(str(reg)) == 0
    assert "no planning dir" in capsys.readouterr().out
