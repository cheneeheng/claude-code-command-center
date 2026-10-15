"""Session title/cwd and usage events (skill, command, agent, interrupt, tool_error)."""

from __future__ import annotations

import json
from pathlib import Path

from claude_usage import load_sessions, parse_file

SID = "abcd1234-0000-0000-0000-000000000000"


def _write(path: Path, records: list[dict]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return str(path)


def _user(content: object, uuid: str, **extra: object) -> dict:
    return {
        "type": "user",
        "uuid": uuid,
        "timestamp": "2026-01-01T10:00:00Z",
        "message": {"role": "user", "content": content},
        **extra,
    }


def _assistant(uuid: str, content: list, msg_id: str | None = None) -> dict:
    return {
        "type": "assistant",
        "uuid": uuid,
        "timestamp": "2026-01-01T10:01:00Z",
        "message": {
            "id": msg_id or f"msg-{uuid}",
            "model": "claude-opus-4-8",
            "usage": {"input_tokens": 1},
            "content": content,
        },
    }


def _tool_use(bid: str, name: str, inp: dict | None = None) -> dict:
    return {"type": "tool_use", "id": bid, "name": name, "input": inp or {}}


def _kinds(fpath: str) -> list[tuple[str, str]]:
    return [(e.kind, e.name) for e in parse_file(fpath).events]


# ── title and cwd ───────────────────────────────────────────────────────────


def test_title_prefers_custom_title_then_first_plain_prompt(tmp_path: Path) -> None:
    proj = tmp_path / "projects" / "p"
    skipped = [
        _user("<command-name>/clear</command-name>", "u1"),
        _user("meta text", "u2", isMeta=True),
        _user([{"type": "tool_result", "tool_use_id": "t0", "content": "x"}], "u3"),
        _user("<local-command-stdout>out</local-command-stdout>", "u4"),
    ]
    long_prompt = "Fix the login bug\nwith more detail" + "x" * 100
    plain = _write(
        proj / "aaaaaaaa-1.jsonl",
        [*skipped, _user([{"type": "text", "text": long_prompt}], "u5"), _assistant("a1", [])],
    )
    titled = _write(
        proj / "bbbbbbbb-2.jsonl",
        [
            _user("first prompt", "u6"),
            {"type": "custom-title", "customTitle": "Old name"},
            {"type": "custom-title", "customTitle": "Renamed"},
            _assistant("a2", []),
        ],
    )
    untitled = _write(proj / "cccccccc-3.jsonl", [*skipped, _assistant("a3", [])])

    assert parse_file(plain).title == "Fix the login bug"
    assert parse_file(titled).title == "Renamed"
    assert parse_file(untitled).title is None
    by_id = {s.session_id: s.title for s in load_sessions([tmp_path])}
    assert by_id == {"aaaaaaaa": "Fix the login bug", "bbbbbbbb": "Renamed", "cccccccc": "cccccccc"}


def test_title_truncates_to_80_characters(tmp_path: Path) -> None:
    path = _write(tmp_path / "projects" / "p" / "s.jsonl", [_user("y" * 200, "u1")])
    assert parse_file(path).title == "y" * 80


def test_cwd_recorded_from_parent_only(tmp_path: Path) -> None:
    proj = tmp_path / "projects" / "p"
    parent = _write(
        proj / f"{SID}.jsonl",
        [_user("hi", "u1", cwd="/old"), _user("again", "u2", cwd="/repo"), _assistant("a1", [])],
    )
    child = _write(
        proj / SID / "subagents" / "agent-x.jsonl",
        [_user("sub prompt", "u3", cwd="/elsewhere"), _assistant("a2", [])],
    )
    assert parse_file(parent).cwd == "/repo"
    assert (parse_file(child).cwd, parse_file(child).title) == (None, None)
    (session,) = load_sessions([tmp_path])
    assert (session.cwd, session.title) == ("/repo", "hi")


# ── events ──────────────────────────────────────────────────────────────────


def test_events_capture_tool_skill_command_agent(tmp_path: Path) -> None:
    path = _write(
        tmp_path / "projects" / "p" / "s.jsonl",
        [
            _user("<command-name>/ceh-x:do-thing</command-name>\n<command-args></command-args>", "u1"),
            _assistant(
                "a1",
                [
                    _tool_use("t1", "Skill", {"skill": "ceh-x:review"}),
                    _tool_use("t2", "Agent", {"subagent_type": "Explore"}),
                    _tool_use("t3", "Task", {}),
                    _tool_use("t4", "Read"),
                ],
            ),
        ],
    )
    events = parse_file(path).events
    assert sorted((e.kind, e.name) for e in events) == sorted(
        [
            ("command", "ceh-x:do-thing"),
            ("tool", "Skill"),
            ("skill", "ceh-x:review"),
            ("tool", "Agent"),
            ("agent", "Explore"),
            ("tool", "Task"),
            ("agent", "general-purpose"),
            ("tool", "Read"),
        ]
    )
    assert {e.key for e in events if e.kind in ("tool", "skill")} >= {"tool:t1", "skill:t1"}
    assert len({e.key for e in events}) == len(events)


def test_events_capture_interrupt_and_tool_error(tmp_path: Path) -> None:
    path = _write(
        tmp_path / "projects" / "p" / "s.jsonl",
        [
            _assistant("a1", [_tool_use("t1", "Bash"), _tool_use("t2", "Read")]),
            _user(
                [
                    {"type": "tool_result", "tool_use_id": "t1", "is_error": True, "content": "boom"},
                    {"type": "tool_result", "tool_use_id": "t2", "content": "fine"},
                    {"type": "tool_result", "tool_use_id": "t9", "is_error": True, "content": "?"},
                ],
                "u1",
            ),
            _user([{"type": "text", "text": "[Request interrupted by user for tool use]"}], "u2"),
            _user("[Request interrupted by user]", "u3"),
        ],
    )
    got = [(k, n) for k, n in _kinds(path) if k != "tool"]
    assert got == [
        ("tool_error", "Bash"),
        ("tool_error", ""),
        ("interrupt", ""),
        ("interrupt", ""),
    ]


def test_markers_inside_tool_result_are_not_events(tmp_path: Path) -> None:
    quoted = "log: [Request interrupted by user] and <command-name>/x</command-name>"
    path = _write(
        tmp_path / "projects" / "p" / "s.jsonl",
        [
            _assistant("a1", [_tool_use("t1", "Read")]),
            _user([{"type": "tool_result", "tool_use_id": "t1", "content": quoted}], "u1"),
            _user([{"type": "tool_result", "tool_use_id": "t1", "content": [
                {"type": "text", "text": "[Request interrupted by user]"}]}], "u2"),
            _user("see <command-name>/y</command-name> in the docs", "u3"),
            # Command-wrapped record without a command name.
            _user("<command-args>--flag</command-args>", "u4"),
        ],
    )
    assert _kinds(path) == [("tool", "Read")]
