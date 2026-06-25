"""Unit tests for `docket init` / `docket doctor` + repo discovery (ITER_02_v2)."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from docket import core


def _reg(tmp_path: Path, obj: dict) -> str:
    reg = tmp_path / "r.json"
    reg.write_text(json.dumps(obj), encoding="utf-8")
    return str(reg)


def _mkrepo(base: Path, rel: str, planning: bool = True) -> Path:
    repo = base / rel
    (repo / ".git").mkdir(parents=True)
    if planning:
        (repo / core.DEFAULT_PLANNING_DIR).mkdir(parents=True)
    return repo


# --- _suffix ------------------------------------------------------------------


@pytest.mark.parametrize(
    "name,expected",
    [
        ("foo", "foo-2"),
        ("foo-2", "foo-3"),
        ("foo-0", "foo-1"),
        ("a-b", "a-b-2"),  # trailing segment not a number -> append -2
    ],
)
def test_suffix(name, expected):
    assert core._suffix(name) == expected


# --- discover_repos -----------------------------------------------------------


def test_discover_repos_filters_dedupes_and_paths(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setattr(core.Path, "home", lambda: home)
    _mkrepo(home, "alpha")  # under home -> ~-relative
    _mkrepo(home, "nest1/same")  # basename collision
    _mkrepo(home, "nest2/same")  # -> deduped to same-2
    _mkrepo(home, "noplan", planning=False)  # no planning dir -> skipped
    _mkrepo(tmp_path / "out", "beta")  # outside home -> absolute

    repos = core.discover_repos(str(tmp_path))
    names = [r["name"] for r in repos]
    assert "alpha" in names
    assert "noplan" not in names
    assert sorted(n for n in names if n.startswith("same")) == ["same", "same-2"]
    assert names == sorted(names)  # output is name-sorted

    alpha = next(r for r in repos if r["name"] == "alpha")
    assert alpha["path"].startswith("~/") and "\\" not in alpha["path"]
    beta = next(r for r in repos if r["name"] == "beta")
    assert not beta["path"].startswith("~/")


# --- cmd_init: fresh ----------------------------------------------------------


def test_cmd_init_fresh_writes_full_config(tmp_path):
    out = tmp_path / ".docket.json"
    summary = core.cmd_init(output=str(out))
    assert out.is_file()
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["port"] == core.DEFAULT_PORT
    assert "$schema" in data
    assert set(data["defaults"]) == set(core.CODE_DEFAULTS)
    assert data["projects"] == []
    assert "wrote" in summary


def test_cmd_init_scan_populates_projects(tmp_path, monkeypatch):
    monkeypatch.setattr(
        core, "discover_repos", lambda root: [{"name": "x", "path": "~/x"}]
    )
    out = tmp_path / ".docket.json"
    core.cmd_init(output=str(out), scan="root")
    assert json.loads(out.read_text())["projects"] == [{"name": "x", "path": "~/x"}]


def test_cmd_init_no_clobber(tmp_path):
    out = tmp_path / ".docket.json"
    out.write_text("{}", encoding="utf-8")
    with pytest.raises(FileExistsError, match="--force"):
        core.cmd_init(output=str(out))


def test_cmd_init_force_overwrites(tmp_path):
    out = tmp_path / ".docket.json"
    out.write_text("OLD", encoding="utf-8")
    core.cmd_init(output=str(out), force=True)
    assert json.loads(out.read_text())["port"] == core.DEFAULT_PORT


def test_cmd_init_dry_run_writes_nothing(tmp_path, capsys):
    out = tmp_path / ".docket.json"
    summary = core.cmd_init(output=str(out), dry_run=True)
    assert not out.exists()
    assert "would write" in summary
    assert '"port"' in capsys.readouterr().out


def test_cmd_init_dry_run_over_existing_does_not_raise(tmp_path):
    out = tmp_path / ".docket.json"
    out.write_text("{}", encoding="utf-8")
    # dry-run must preview even when the file exists, without no-clobber tripping
    assert "would write" in core.cmd_init(output=str(out), dry_run=True)


# --- cmd_init: merge ----------------------------------------------------------


def test_cmd_init_merge_requires_existing_target(tmp_path):
    with pytest.raises(FileNotFoundError, match="does not exist"):
        core.cmd_init(output=str(tmp_path / "nope.json"), merge=True)


def test_cmd_init_merge_adds_only_new_and_preserves(tmp_path, monkeypatch):
    out = tmp_path / ".docket.json"
    out.write_text(
        json.dumps({"port": 8765, "projects": [{"name": "old", "path": "~/old"}]}),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        core,
        "discover_repos",
        lambda root: [
            {"name": "old", "path": "~/old"},  # same path already listed -> skip
            {"name": "new", "path": "~/new"},
        ],
    )
    summary = core.cmd_init(output=str(out), scan="x", merge=True)
    data = json.loads(out.read_text())
    assert [p["name"] for p in data["projects"]] == ["new", "old"]  # sorted, preserved
    assert data["port"] == 8765
    assert "added 1" in summary


def test_cmd_init_merge_name_collision_suffixes(tmp_path, monkeypatch):
    out = tmp_path / ".docket.json"
    out.write_text(
        json.dumps({"projects": [{"name": "dup", "path": "~/a"}]}), encoding="utf-8"
    )
    monkeypatch.setattr(
        core, "discover_repos", lambda root: [{"name": "dup", "path": "~/b"}]
    )
    core.cmd_init(output=str(out), scan="x", merge=True)
    names = sorted(p["name"] for p in json.loads(out.read_text())["projects"])
    assert names == ["dup", "dup-2"]


def test_cmd_init_merge_dry_run_previews(tmp_path, monkeypatch, capsys):
    out = tmp_path / ".docket.json"
    out.write_text(json.dumps({"projects": []}), encoding="utf-8")
    monkeypatch.setattr(
        core, "discover_repos", lambda root: [{"name": "n", "path": "~/n"}]
    )
    summary = core.cmd_init(output=str(out), scan="x", merge=True, dry_run=True)
    assert "would add 1" in summary
    assert json.loads(out.read_text())["projects"] == []  # unchanged on disk
    assert '"n"' in capsys.readouterr().out


# --- cmd_doctor ---------------------------------------------------------------


def test_doctor_load_error_returns_1(tmp_path, capsys):
    assert core.cmd_doctor(_reg(tmp_path, ["bad shape"])) == 1
    assert "error:" in capsys.readouterr().out


def test_doctor_no_projects_warns_but_clean(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        core.os.path, "expanduser", lambda p: p.replace("~", str(tmp_path))
    )
    assert core.cmd_doctor(None) == 0
    assert "no projects" in capsys.readouterr().out


def test_doctor_clean_project(tmp_path, project, capsys):
    reg = _reg(tmp_path, {"projects": [{"name": "repo", "path": project.path}]})
    assert core.cmd_doctor(reg) == 0
    assert "0 error(s)" in capsys.readouterr().out


def test_doctor_missing_planning_dir_warns(tmp_path, project, capsys):
    shutil.rmtree(Path(project.path) / core.DEFAULT_PLANNING_DIR)
    reg = _reg(tmp_path, {"projects": [{"name": "repo", "path": project.path}]})
    assert core.cmd_doctor(reg) == 0  # warn-level only
    assert "no planning dir" in capsys.readouterr().out


def test_doctor_bad_permission_mode_errors(tmp_path, project, capsys):
    reg = _reg(
        tmp_path,
        {
            "defaults": {"permission_mode": "bogus"},
            "projects": [{"name": "repo", "path": project.path}],
        },
    )
    assert core.cmd_doctor(reg) == 1
    assert "unknown permission_mode" in capsys.readouterr().out


def test_doctor_empty_allowed_tools_warns(tmp_path, project, capsys):
    reg = _reg(
        tmp_path,
        {
            "defaults": {"allowed_tools": []},
            "projects": [{"name": "repo", "path": project.path}],
        },
    )
    assert core.cmd_doctor(reg) == 0  # warn-level only
    assert "allowed_tools is empty" in capsys.readouterr().out


def test_doctor_missing_claude_bin_errors(tmp_path, project, monkeypatch, capsys):
    monkeypatch.setattr(core.shutil, "which", lambda b: None)
    reg = _reg(tmp_path, {"projects": [{"name": "repo", "path": project.path}]})
    assert core.cmd_doctor(reg) == 1
    assert "not found on PATH" in capsys.readouterr().out
