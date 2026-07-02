"""Unit tests for instruction resolution, event formatting, tool digest."""

import pytest

from docket import core


# --- resolve_instruction ------------------------------------------------------


def test_resolve_instruction_default_template(project):
    out = core.resolve_instruction(project, "alpha", None)
    assert ".agents_workspace/planning/alpha.md" in out


def test_resolve_instruction_uses_project_template(project):
    project.instruction_template = "Do {path} please"
    assert (
        core.resolve_instruction(project, "a/b", None)
        == "Do .agents_workspace/planning/a/b.md please"
    )


def test_resolve_instruction_honours_project_planning_dir(project):
    project.planning_dir = "plans"
    project.instruction_template = "Run {path}"
    assert core.resolve_instruction(project, "x", None) == "Run plans/x.md"


def test_resolve_instruction_override_with_path(project):
    assert (
        core.resolve_instruction(project, "x", "Run {path}")
        == "Run .agents_workspace/planning/x.md"
    )


def test_resolve_instruction_override_verbatim_no_path(project):
    assert core.resolve_instruction(project, "x", "just do it") == "just do it"


def test_resolve_instruction_validates_slug(project):
    with pytest.raises(ValueError):
        core.resolve_instruction(project, "../x", None)


# --- default_instruction_template (param-less /api/instruction-template) -------


def test_default_template_no_registry(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(
        core.os.path, "expanduser", lambda p: p.replace("~", str(tmp_path))
    )
    assert core.default_instruction_template(None) == core.DEFAULT_INSTRUCTION_TEMPLATE


def test_default_template_from_defaults_layer(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text(
        '{"defaults": {"instruction_template": "D {path}"}, "projects": []}',
        encoding="utf-8",
    )
    assert core.default_instruction_template(str(reg)) == "D {path}"


def test_default_template_v1_carryover(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text(
        '{"instruction_template": "V1 {path}", "projects": []}', encoding="utf-8"
    )
    assert core.default_instruction_template(str(reg)) == "V1 {path}"


def test_default_template_non_dict_registry(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text("[1, 2, 3]", encoding="utf-8")
    assert (
        core.default_instruction_template(str(reg)) == core.DEFAULT_INSTRUCTION_TEMPLATE
    )


def test_default_template_empty_defaults_falls_back(tmp_path):
    reg = tmp_path / "r.json"
    reg.write_text('{"defaults": {}, "projects": []}', encoding="utf-8")
    assert (
        core.default_instruction_template(str(reg)) == core.DEFAULT_INSTRUCTION_TEMPLATE
    )


# --- format_event -------------------------------------------------------------


def test_format_event_blank_returns_none():
    assert core.format_event("   \n") is None


def test_format_event_non_json_passthrough():
    assert core.format_event("not json at all") == "not json at all"


def test_format_event_system_skipped():
    assert core.format_event('{"type": "system"}') is None


def test_format_event_assistant_text():
    ev = '{"type":"assistant","message":{"content":[{"type":"text","text":" hi "}]}}'
    assert core.format_event(ev) == "hi"


def test_format_event_assistant_tool_use_with_digest():
    ev = (
        '{"type":"assistant","message":{"content":'
        '[{"type":"tool_use","name":"Edit","input":{"file_path":"a/b.py"}}]}}'
    )
    assert core.format_event(ev) == "▸ Edit a/b.py"


def test_format_event_assistant_tool_use_no_digest():
    ev = (
        '{"type":"assistant","message":{"content":'
        '[{"type":"tool_use","name":"Think","input":{}}]}}'
    )
    assert core.format_event(ev) == "▸ Think"


def test_format_event_assistant_other_block_skipped():
    # a content block that is neither text nor tool_use is ignored
    ev = '{"type":"assistant","message":{"content":[{"type":"thinking","text":"hmm"}]}}'
    assert core.format_event(ev) is None


def test_format_event_assistant_empty_content_returns_none():
    ev = '{"type":"assistant","message":{"content":[{"type":"text","text":"   "}]}}'
    assert core.format_event(ev) is None


def test_format_event_result_success():
    assert core.format_event('{"type":"result","subtype":"success"}') == "[done]"


def test_format_event_result_is_error():
    assert core.format_event('{"type":"result","is_error":true}') == "[error] error"


def test_format_event_result_error_subtype():
    out = core.format_event('{"type":"result","subtype":"error_max_turns"}')
    assert out == "[error] error_max_turns"


def test_format_event_unknown_type_returns_none():
    assert core.format_event('{"type":"user"}') is None


# --- _tool_digest -------------------------------------------------------------


def test_tool_digest_first_line_only():
    long = "x" * 200
    assert core._tool_digest({"command": f"line1\n{long}"}) == "line1"


def test_tool_digest_empty_string_value():
    assert core._tool_digest({"file_path": ""}) == ""


def test_tool_digest_no_known_keys():
    assert core._tool_digest({"other": "z"}) == ""
