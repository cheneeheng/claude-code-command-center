"""Unit tests for transcript discovery and parsing (the public sessions API)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from claude_usage import claude_dirs, load_sessions, load_usage, transcript_files
from claude_usage.pricing import estimated_cost
from claude_usage.sessions import ACTIVITY_DAYS, _parse_ts, _read_records


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


# ── load_usage / Activity ───────────────────────────────────────────────────

from datetime import datetime, timedelta, timezone  # noqa: E402


def _recent_utc(days_ago: int, hour: int = 12) -> datetime:
    """A UTC timestamp `days_ago` days back at a fixed hour (well inside a day)."""
    base = datetime.now(timezone.utc).replace(
        hour=hour, minute=0, second=0, microsecond=0
    )
    return base - timedelta(days=days_ago)


def _daily_by_date(activity: object) -> dict[str, object]:
    return {b.date: b for b in activity.daily}  # type: ignore[attr-defined]


def test_load_usage_sessions_match_load_sessions(tmp_path: Path) -> None:
    usage = {
        "input_tokens": 100,
        "output_tokens": 200,
        "cache_creation_input_tokens": 10,
        "cache_read_input_tokens": 20,
    }
    _write_transcript(
        tmp_path, "p", "sess", [_assistant("claude-opus-4-8", usage, uuid="a1")]
    )
    sessions, _ = load_usage([tmp_path])
    assert sessions == load_sessions([tmp_path])


def test_activity_attributes_message_to_its_own_local_day(tmp_path: Path) -> None:
    usage = {"input_tokens": 10, "output_tokens": 5}
    ts1, ts2 = _recent_utc(3), _recent_utc(2)  # two consecutive UTC noons
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-opus-4-8", usage, uuid="a1", ts=ts1.isoformat()),
            _assistant("claude-opus-4-8", usage, uuid="a2", ts=ts2.isoformat()),
        ],
    )
    _, activity = load_usage([tmp_path])
    by_date = _daily_by_date(activity)
    d1, d2 = ts1.astimezone().date().isoformat(), ts2.astimezone().date().isoformat()
    assert d1 != d2
    assert by_date[d1].tokens == 15
    assert by_date[d2].tokens == 15


def test_activity_hour_and_weekday_bucketing(tmp_path: Path) -> None:
    usage = {"input_tokens": 40, "output_tokens": 2}
    ts = _recent_utc(5, hour=9)
    _write_transcript(
        tmp_path, "p", "sess", [_assistant("claude-sonnet-5", usage, uuid="a1", ts=ts.isoformat())]
    )
    _, activity = load_usage([tmp_path])
    local = ts.astimezone()
    assert activity.hour_dow[local.weekday()][local.hour] == 42
    # No other cell holds tokens.
    total = sum(sum(row) for row in activity.hour_dow)
    assert total == 42


def test_activity_counts_tool_use_blocks(tmp_path: Path) -> None:
    usage = {"input_tokens": 5, "output_tokens": 5}
    list_msg = _assistant("claude-opus-4-8", usage, uuid="a1", ts=_recent_utc(1).isoformat())
    list_msg["message"]["content"] = [
        {"type": "tool_use", "name": "Read"},
        {"type": "tool_use", "name": "Read"},
        {"type": "tool_use", "name": "Edit"},
        {"type": "text", "text": "hi"},
        {"type": "tool_use"},  # missing name -> skipped
    ]
    str_msg = _assistant("claude-opus-4-8", usage, uuid="a2", ts=_recent_utc(1).isoformat())
    str_msg["message"]["content"] = "just text, no tools"
    _write_transcript(tmp_path, "p", "sess", [list_msg, str_msg])
    _, activity = load_usage([tmp_path])
    assert activity.tools == {"Read": 2, "Edit": 1}


def test_activity_per_family_aggregates_versions(tmp_path: Path) -> None:
    usage = {"input_tokens": 10, "output_tokens": 0}
    ts = _recent_utc(4)
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-opus-4-7", usage, uuid="a1", ts=ts.isoformat()),
            _assistant("claude-opus-4-8", usage, uuid="a2", ts=ts.isoformat()),
            _assistant("<synthetic>", usage, uuid="a3", ts=ts.isoformat()),
        ],
    )
    _, activity = load_usage([tmp_path])
    bucket = _daily_by_date(activity)[ts.astimezone().date().isoformat()]
    # Both opus versions fold into one family; synthetic (unknown) is excluded.
    assert bucket.per_family == {"claude-opus": 20}


def test_activity_handles_naive_timestamp_and_zero_token_message(tmp_path: Path) -> None:
    real = _recent_utc(2)
    naive_ts = real.replace(tzinfo=None).isoformat()  # no offset -> treated as UTC
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-opus-4-8", {"input_tokens": 12}, uuid="a1", ts=naive_ts),
            # Zero-token assistant message: kept for the session, skipped by Activity.
            _assistant("claude-opus-4-8", {"input_tokens": 0}, uuid="a2", ts=naive_ts),
        ],
    )
    _, activity = load_usage([tmp_path])
    day = real.astimezone().date().isoformat()
    assert _daily_by_date(activity)[day].tokens == 12
    assert sum(b.tokens for b in activity.daily) == 12


def test_activity_padding_length_and_cutoff(tmp_path: Path) -> None:
    usage = {"input_tokens": 7, "output_tokens": 0}
    recent = _recent_utc(1)
    old = _recent_utc(400)  # older than the 364-day window
    _write_transcript(
        tmp_path,
        "p",
        "sess",
        [
            _assistant("claude-opus-4-8", usage, uuid="a1", ts=recent.isoformat()),
            _assistant("claude-opus-4-8", usage, uuid="a2", ts=old.isoformat()),
        ],
    )
    sessions, activity = load_usage([tmp_path])
    assert len(activity.daily) == ACTIVITY_DAYS
    dates = [b.date for b in activity.daily]
    assert dates == sorted(dates)  # oldest first
    assert dates[-1] == datetime.now().astimezone().date().isoformat()
    # The 400-day-old message is dropped from Activity but the session still carries it.
    assert sum(b.tokens for b in activity.daily) == 7
    assert sessions[0].input_tokens == 14
