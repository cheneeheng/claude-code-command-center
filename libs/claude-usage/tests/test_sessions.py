"""Unit tests for transcript discovery and parsing (the public sessions API)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from claude_usage import claude_dirs, load_sessions, transcript_files
from claude_usage.pricing import estimated_cost
from claude_usage.sessions import _parse_ts, _read_records


def _write_transcript(claude_dir: Path, project: str, stem: str, records: list[dict]) -> Path:
    """Write records as JSONL under <claude_dir>/projects/<project>/<stem>.jsonl."""
    proj = claude_dir / "projects" / project
    proj.mkdir(parents=True, exist_ok=True)
    path = proj / f"{stem}.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return path


def _assistant(model: str, usage: dict, uuid: str = "", ts: str = "") -> dict:
    rec: dict = {"type": "assistant", "message": {"model": model, "usage": usage}}
    if uuid:
        rec["uuid"] = uuid
    if ts:
        rec["timestamp"] = ts
    return rec


def usage_counts(usage: dict) -> dict:
    """Translate a transcript usage blob into the library's TokenCounts keys."""
    return {
        "input": usage["input_tokens"],
        "output": usage["output_tokens"],
        "cache_write": usage["cache_creation_input_tokens"],
        "cache_read": usage["cache_read_input_tokens"],
    }


# ── claude_dirs ─────────────────────────────────────────────────────────────

def test_claude_dirs_defaults_to_home(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("C4_CLAUDE_DIR", raising=False)
    assert claude_dirs() == [Path.home() / ".claude"]


def test_claude_dirs_honours_env_pathsep_and_skips_blanks(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("C4_CLAUDE_DIR", f"/a{os.pathsep}{os.pathsep}/b")
    assert claude_dirs() == [Path("/a"), Path("/b")]


# ── transcript_files ────────────────────────────────────────────────────────

def test_transcript_files_finds_recursively_sorted_and_deduped(tmp_path: Path) -> None:
    _write_transcript(tmp_path, "proj-a", "sess1", [{"type": "user"}])
    _write_transcript(tmp_path, "proj-b", "sess2", [{"type": "user"}])
    files = transcript_files([tmp_path])
    assert len(files) == 2
    assert files == sorted(files)
    assert all(f.endswith(".jsonl") for f in files)


def test_transcript_files_defaults_to_claude_dirs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _write_transcript(tmp_path, "proj", "sess", [{"type": "user"}])
    monkeypatch.setenv("C4_CLAUDE_DIR", str(tmp_path))
    assert len(transcript_files()) == 1


# ── load_sessions: happy path ───────────────────────────────────────────────

def test_load_sessions_rolls_up_tokens_cost_and_metadata(tmp_path: Path) -> None:
    usage = {
        "input_tokens": 100,
        "output_tokens": 200,
        "cache_creation_input_tokens": 10,
        "cache_read_input_tokens": 20,
    }
    _write_transcript(
        tmp_path,
        "myproject",
        "abc12345def",
        [
            {"type": "user", "uuid": "u1", "timestamp": "2026-01-01T10:00:00Z"},
            _assistant("claude-opus-4-8", usage, uuid="a1", ts="2026-01-01T10:01:00Z"),
        ],
    )
    (session,) = load_sessions([tmp_path])
    assert session.session_id == "abc12345"
    assert session.project == "myproject"
    assert session.models == ["claude-opus-4-8"]
    assert session.input_tokens == 100
    assert session.output_tokens == 200
    assert session.cache_write_tokens == 10
    assert session.cache_read_tokens == 20
    assert session.total_tokens == 330
    assert session.message_count == 1
    assert session.first_ts == "2026-01-01T10:00:00+00:00"
    assert session.last_ts == "2026-01-01T10:01:00+00:00"
    assert session.cost_usd == estimated_cost({"claude-opus-4-8": usage_counts(usage)})


def test_load_sessions_dedups_by_uuid_and_folds_synthetic_into_unknown(
    tmp_path: Path,
) -> None:
    usage = {"input_tokens": 50, "output_tokens": 50}
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-sonnet-5", usage, uuid="a1"),
            _assistant("claude-sonnet-5", usage, uuid="a1"),  # duplicate uuid -> skipped
            _assistant("<synthetic>", {"input_tokens": 7}, uuid="a2"),  # -> unknown
        ],
    )
    (session,) = load_sessions([tmp_path])
    # Only the sonnet model is exposed; synthetic is folded into the excluded "unknown".
    assert session.models == ["claude-sonnet-5"]
    assert "unknown" not in session.per_model
    # Dedup: one sonnet message counted, not two. Synthetic still counts as a message.
    assert session.message_count == 2
    # Totals include the synthetic (unknown) tokens even though it has no model row.
    assert session.input_tokens == 50 + 7


def test_load_sessions_tracks_min_and_max_ts_out_of_order(tmp_path: Path) -> None:
    usage = {"input_tokens": 10, "output_tokens": 10}
    # Second record is chronologically earlier than the first (out-of-order log).
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-opus-4-8", usage, uuid="a1", ts="2026-06-01T00:00:00Z"),
            _assistant("claude-opus-4-8", usage, uuid="a2", ts="2026-01-01T00:00:00Z"),
        ],
    )
    (session,) = load_sessions([tmp_path])
    assert session.first_ts == "2026-01-01T00:00:00+00:00"
    assert session.last_ts == "2026-06-01T00:00:00+00:00"


def test_load_sessions_sorts_newest_first(tmp_path: Path) -> None:
    usage = {"input_tokens": 10, "output_tokens": 10}
    _write_transcript(
        tmp_path, "p", "older", [_assistant("claude-opus-4-8", usage, ts="2026-01-01T00:00:00Z")]
    )
    _write_transcript(
        tmp_path, "p", "newer", [_assistant("claude-opus-4-8", usage, ts="2026-06-01T00:00:00Z")]
    )
    sessions = load_sessions([tmp_path])
    assert [s.session_id for s in sessions] == ["newer", "older"]


# ── load_sessions: sessions that must be dropped ────────────────────────────

def test_load_sessions_drops_empty_invalid_and_usageless(tmp_path: Path) -> None:
    # Empty file.
    (tmp_path / "projects" / "p").mkdir(parents=True)
    (tmp_path / "projects" / "p" / "empty.jsonl").write_text("\n", encoding="utf-8")
    # Only invalid JSON and a user message -> no assistant usage.
    (tmp_path / "projects" / "p" / "junk.jsonl").write_text(
        "not json\n" + json.dumps({"type": "user"}) + "\n", encoding="utf-8"
    )
    # Assistant message but zero tokens -> dropped.
    _write_transcript(
        tmp_path, "p", "zero", [_assistant("claude-opus-4-8", {"input_tokens": 0})]
    )
    assert load_sessions([tmp_path]) == []


# ── private helpers: defensive branches ─────────────────────────────────────

def test_read_records_returns_empty_on_oserror(tmp_path: Path) -> None:
    # Opening a directory raises OSError -> graceful empty list.
    assert _read_records(str(tmp_path)) == []


def test_parse_ts_handles_missing_and_invalid() -> None:
    assert _parse_ts(None) is None
    assert _parse_ts("") is None
    assert _parse_ts(12345) is None
    assert _parse_ts("not-a-date") is None
    assert _parse_ts("2026-01-01T00:00:00Z") is not None
