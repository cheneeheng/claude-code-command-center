"""Accuracy tests: global dedup, tool-block dedup, subagent folding, prices."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from claude_usage import (
    MODEL_COSTS,
    ModelPrice,
    estimated_cost,
    load_sessions,
    load_usage,
    model_costs,
    parse_file,
    price_for,
)


def _write(path: Path, records: list[dict]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return path


def _line(
    msg_id: str,
    uuid: str,
    usage: dict,
    content: list | None = None,
    req: str = "req1",
    ts: str = "2026-01-01T10:00:00Z",
    model: str = "claude-opus-4-8",
) -> dict:
    """One streamed assistant line: message.id + requestId shared, uuid unique."""
    return {
        "type": "assistant",
        "uuid": uuid,
        "requestId": req,
        "timestamp": ts,
        "message": {
            "id": msg_id,
            "model": model,
            "usage": usage,
            "content": content or [],
        },
    }


def _tool(block_id: str | None, name: str) -> dict:
    block = {"type": "tool_use", "name": name}
    if block_id:
        block["id"] = block_id
    return block


# ── dedup ───────────────────────────────────────────────────────────────────


def test_dedup_keeps_last_usage_per_message_id(tmp_path: Path) -> None:
    _write(
        tmp_path / "projects" / "p" / "sess.jsonl",
        [
            _line("m1", "u1", {"input_tokens": 10, "output_tokens": 1}),
            _line("m1", "u2", {"input_tokens": 10, "output_tokens": 50}),
        ],
    )
    (session,) = load_sessions([tmp_path])
    assert session.message_count == 1
    assert session.input_tokens == 10
    assert session.output_tokens == 50


def test_split_message_keeps_every_tool_use(tmp_path: Path) -> None:
    usage = {"input_tokens": 1}
    _write(
        tmp_path / "projects" / "p" / "sess.jsonl",
        [
            _line("m1", "u1", usage, [_tool("t1", "Read")]),
            # Second line of the same message repeats t1 and adds t2.
            _line("m1", "u2", usage, [_tool("t1", "Read"), _tool("t2", "Edit")]),
        ],
    )
    _, activity = load_usage([tmp_path])
    assert activity.tools == {"Read": 1, "Edit": 1}


def test_id_less_tool_blocks_each_count(tmp_path: Path) -> None:
    _write(
        tmp_path / "projects" / "p" / "sess.jsonl",
        [_line("m1", "u1", {"input_tokens": 1}, [_tool(None, "Read")] * 2)],
    )
    _, activity = load_usage([tmp_path])
    assert activity.tools == {"Read": 2}


def test_dedup_is_global_across_files(tmp_path: Path) -> None:
    usage = {"input_tokens": 100}
    proj = tmp_path / "projects" / "p"
    _write(proj / "aaaaaaaa-1.jsonl", [_line("m1", "u1", usage)])
    # A resumed session copies the same reply into a new file.
    _write(proj / "bbbbbbbb-2.jsonl", [_line("m1", "u9", usage), _line("m2", "u3", usage)])
    sessions = load_sessions([tmp_path])
    assert sum(s.input_tokens for s in sessions) == 200
    assert sum(s.message_count for s in sessions) == 2


def test_message_keeps_first_session_id(tmp_path: Path) -> None:
    proj = tmp_path / "projects" / "p"
    _write(proj / "aaaaaaaa-1.jsonl", [_line("m1", "u1", {"input_tokens": 5})])
    _write(
        proj / "bbbbbbbb-2.jsonl",
        [_line("m1", "u9", {"input_tokens": 7}), _line("m2", "u3", {"input_tokens": 1})],
    )
    by_id = {s.session_id: s for s in load_sessions([tmp_path])}
    # Last line wins for the counts, but m1 stays with the session that saw it first.
    assert by_id["aaaaaaaa"].input_tokens == 7
    assert by_id["bbbbbbbb"].input_tokens == 1


# ── subagent and workflow folding ───────────────────────────────────────────


def test_subagent_and_workflow_files_fold_into_parent(tmp_path: Path) -> None:
    sid = "abcd1234-0000-0000-0000-000000000000"
    proj = tmp_path / "projects" / "p"
    _write(proj / f"{sid}.jsonl", [_line("m1", "u1", {"input_tokens": 1})])
    _write(proj / sid / "subagents" / "agent-a.jsonl", [_line("m2", "u2", {"input_tokens": 2})])
    _write(
        proj / sid / "subagents" / "workflows" / "wf_1" / "agent-b.jsonl",
        [_line("m3", "u3", {"input_tokens": 4})],
    )
    (session,) = load_sessions([tmp_path])
    assert session.session_id == "abcd1234"
    assert session.project == "p"
    assert session.input_tokens == 7
    assert session.message_count == 3


def test_orphan_subagent_folder_creates_session(tmp_path: Path) -> None:
    sid = "feed5678-0000-0000-0000-000000000000"
    _write(
        tmp_path / "projects" / "p" / sid / "subagents" / "agent-a.jsonl",
        [_line("m1", "u1", {"input_tokens": 3})],
    )
    (session,) = load_sessions([tmp_path])
    assert session.session_id == "feed5678"
    assert session.project == "p"
    assert session.input_tokens == 3


def test_parse_file_outside_projects_and_malformed_records(tmp_path: Path) -> None:
    path = _write(
        tmp_path / "loose" / "abcdefghij.jsonl",
        [
            {"type": "assistant", "uuid": "u1", "message": "not a dict"},
            {"type": "assistant", "uuid": "u2", "message": {"usage": "nope"}},
        ],
    )
    fp = parse_file(str(path))
    assert (fp.project, fp.session_id) == ("loose", "abcdefgh")
    assert [m.input for m in fp.messages] == [0, 0]


# ── pricing ─────────────────────────────────────────────────────────────────


def test_price_for_prefix_fallback_and_unknown() -> None:
    assert price_for("claude-opus-5-5") == ModelPrice(4.0, 20.0, 5.0, 0.20, 8.0)
    assert price_for("claude-opus-4-8") == ModelPrice(5.0, 25.0, 6.25, 0.50, 10.0)
    assert price_for("claude-opus-4-1-20250805") == ModelPrice(15.0, 75.0, 18.75, 1.50, 30.0)
    assert price_for("claude-fable-5-1") == ModelPrice(10.0, 50.0, 12.5, 0.25, 20.0)
    assert price_for("claude-haiku-4-5-20251001") == ModelPrice(1.0, 5.0, 1.25, 0.10, 2.0)
    assert price_for("claude-3-5-haiku-20241022") == ModelPrice(0.8, 4.0, 1.0, 0.08, 1.6)
    # Unknown version of a known family -> family fallback.
    assert price_for("claude-sonnet-9") == ModelPrice(*MODEL_COSTS["claude-sonnet"], 6.0)
    assert price_for("gpt-4o") is None
    assert price_for("") is None


def test_model_costs_agrees_with_price_for() -> None:
    for model in ("claude-opus-5-5", "claude-sonnet-4-6", "claude-haiku-5-5", "gpt-4o"):
        price = price_for(model)
        expected = None if price is None else (
            price.input, price.output, price.cache_write, price.cache_read
        )
        assert model_costs(model) == expected


def test_estimated_cost_prices_one_hour_cache_writes_at_double_input() -> None:
    tok = {
        "input": 0,
        "output": 0,
        "cache_write": 1_000_000,
        "cache_write_1h": 1_000_000,
        "cache_read": 0,
    }
    # 1M 5-minute writes at 6.25 + 1M 1-hour writes at 10.00 for Opus 4.8.
    assert estimated_cost({"claude-opus-4-8": tok}) == pytest.approx(16.25)


def test_one_hour_cache_writes_parsed_from_transcript(tmp_path: Path) -> None:
    usage = {
        "input_tokens": 0,
        "cache_creation_input_tokens": 3_000_000,
        "cache_creation": {
            "ephemeral_5m_input_tokens": 1_000_000,
            "ephemeral_1h_input_tokens": 2_000_000,
        },
    }
    _write(tmp_path / "projects" / "p" / "sess.jsonl", [_line("m1", "u1", usage)])
    (session,) = load_sessions([tmp_path])
    assert session.cache_write_tokens == 3_000_000
    assert session.cost_usd == pytest.approx(6.25 + 20.0)
    # Consumers sum per-model values for totals (usage-report does), so the keys
    # must not overlap.
    assert sum(session.per_model["claude-opus-4-8"].values()) == session.total_tokens
