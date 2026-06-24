"""Unit tests for core registry loading, the layer cascade, and search-path resolution."""

import json

import pytest

from docket import core


def test_no_registry_returns_empty_config(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)  # no ./.docket.json here
    monkeypatch.setattr(
        core.os.path, "expanduser", lambda p: p.replace("~", str(tmp_path))
    )
    cfg = core.load_registry(None)
    assert cfg.projects == []
    assert cfg.port == core.DEFAULT_PORT


def test_search_paths_order(monkeypatch):
    monkeypatch.setenv("DOCKET_REGISTRY", "/env/reg.json")
    paths = core.registry_search_paths("/flag/reg.json")
    assert paths[0].endswith("reg.json") and "flag" in paths[0]
    assert any("env" in p for p in paths)
    assert any(p.endswith(".docket.json") for p in paths)


def test_load_via_env_var(monkeypatch, registry_file):
    monkeypatch.setenv("DOCKET_REGISTRY", registry_file)
    cfg = core.load_registry(None)
    assert len(cfg.projects) == 1
    assert cfg.projects[0].name == "repo"
    # top-level instruction_template (v1 shape) is leniently promoted into defaults
    assert cfg.projects[0].instruction_template == "Implement {path} now."


def test_load_full_entry_fields(tmp_path, project):
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps(
            {
                "projects": [
                    {
                        "name": "x",
                        "path": project.path,
                        "allowed_tools": ["Read"],
                        "model": "claude-sonnet-4-6",
                        "max_turns": 40,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    p = core.load_registry(str(reg)).projects[0]
    assert p.allowed_tools == ["Read"]
    assert p.model == "claude-sonnet-4-6"
    assert p.max_turns == 40
    # everything unset falls back to the code constant
    assert p.instruction_template == core.DEFAULT_INSTRUCTION_TEMPLATE
    assert p.permission_mode == core.DEFAULT_PERMISSION_MODE
    assert p.planning_dir == core.DEFAULT_PLANNING_DIR
    assert p.implementation_dir == core.DEFAULT_IMPL_DIR
    assert p.claude_bin == core.DEFAULT_CLAUDE_BIN
    assert p.claude_extra_args == []


def test_cascade_defaults_then_project_override(tmp_path, project):
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps(
            {
                "port": 9999,
                "defaults": {
                    "max_turns": 50,
                    "permission_mode": "plan",
                    "planning_dir": "plans",
                    "claude_extra_args": ["--add-dir", "/x"],
                },
                "projects": [
                    {"name": "a", "path": project.path},  # inherits defaults
                    {
                        "name": "b",
                        "path": project.path,
                        "max_turns": 7,  # overrides the defaults layer
                    },
                ],
            }
        ),
        encoding="utf-8",
    )
    cfg = core.load_registry(str(reg))
    assert cfg.port == 9999
    a, b = cfg.projects
    assert a.max_turns == 50 and a.permission_mode == "plan"
    assert a.planning_dir == "plans"
    assert a.claude_extra_args == ["--add-dir", "/x"]
    # the list is copied, not shared with the defaults dict
    a.claude_extra_args.append("mutated")
    assert b.claude_extra_args == ["--add-dir", "/x"]
    assert b.max_turns == 7  # project override wins over defaults


def test_explicit_top_level_instruction_template_not_overridden_by_v1(
    tmp_path, project
):
    # a defaults.instruction_template takes precedence over a stray top-level one
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps(
            {
                "instruction_template": "top {path}",
                "defaults": {"instruction_template": "defaults {path}"},
                "projects": [{"name": "x", "path": project.path}],
            }
        ),
        encoding="utf-8",
    )
    p = core.load_registry(str(reg)).projects[0]
    assert p.instruction_template == "defaults {path}"


def test_path_expands_env_var(tmp_path, project, monkeypatch):
    monkeypatch.setenv("DOCKET_TEST_ROOT", str(tmp_path / "repo"))
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "x", "path": "$DOCKET_TEST_ROOT"}]}),
        encoding="utf-8",
    )
    p = core.load_registry(str(reg)).projects[0]
    assert p.path == str(tmp_path / "repo")


def test_bad_top_level_shape(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text(json.dumps(["not", "a", "dict"]), encoding="utf-8")
    with pytest.raises(ValueError, match="expected top-level shape"):
        core.load_registry(str(reg))


def test_missing_name(tmp_path, project):
    reg = tmp_path / "r.json"
    reg.write_text(json.dumps({"projects": [{"path": project.path}]}), encoding="utf-8")
    with pytest.raises(ValueError, match="missing 'name'"):
        core.load_registry(str(reg))


def test_duplicate_name(tmp_path, project):
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps(
            {
                "projects": [
                    {"name": "dup", "path": project.path},
                    {"name": "dup", "path": project.path},
                ]
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate project name"):
        core.load_registry(str(reg))


def test_missing_path(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text(json.dumps({"projects": [{"name": "x"}]}), encoding="utf-8")
    with pytest.raises(ValueError, match="missing 'path'"):
        core.load_registry(str(reg))


def test_path_not_a_directory(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text(
        json.dumps(
            {
                "projects": [
                    {"name": "x", "path": str(tmp_path / "nope")},
                ]
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="not a directory"):
        core.load_registry(str(reg))
