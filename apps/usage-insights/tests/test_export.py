"""Store and exporter: incremental, upsert-only, lock-aware."""

from __future__ import annotations

import shutil
import sqlite3
from pathlib import Path

import pytest

from usage_insights import cli, export, store


def _rows(db: Path, sql: str) -> list[tuple[object, ...]]:
    with sqlite3.connect(db) as conn:
        return conn.execute(sql).fetchall()


def test_export_counts_match_fixture(claude_dir: Path, db: Path) -> None:
    result = export.run_export(db, [claude_dir])
    assert (result.files_scanned, result.files_parsed) == (3, 3)
    assert (result.messages, result.events) == (4, 10)
    assert _rows(db, "SELECT id, project, title, cwd FROM sessions ORDER BY id") == [
        ("11111111", "C--work-alpha", "Alpha work", "/work/alpha"),
        ("22222222", "C--work-beta", "Beta prompt", "/work/beta"),
    ]
    assert _rows(
        db,
        "SELECT session_id, input, output, cache_write, cache_read, cache_write_1h "
        "FROM messages WHERE key LIKE 'm1:%'",
    ) == [("11111111", 100, 50, 400, 0, 600)]
    kinds = _rows(db, "SELECT kind, name FROM events ORDER BY key")
    assert ("skill", "my-skill") in kinds
    assert ("command", "my-skill") in kinds
    assert ("tool_error", "Read") in kinds
    assert ("agent", "Explore") in kinds
    assert _rows(db, "SELECT started, ended FROM sessions WHERE id = '11111111'") == [
        ("2026-10-01T09:01:05+00:00", "2026-10-01T09:06:30+00:00")
    ]
    assert _rows(db, "SELECT value FROM meta WHERE key = 'last_export'")[0][0]


def test_export_skips_unchanged_files(
    claude_dir: Path, db: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    export.run_export(db, [claude_dir])
    calls: list[str] = []
    real = export.parse_file
    monkeypatch.setattr(export, "parse_file", lambda p: calls.append(p) or real(p))
    first = _rows(db, "SELECT value FROM meta WHERE key = 'last_export'")
    result = export.run_export(db, [claude_dir])
    assert (result.files_scanned, result.files_parsed, calls) == (3, 0, [])
    assert _rows(db, "SELECT value FROM meta WHERE key = 'last_export'") >= first

    beta = next(claude_dir.rglob("22222222-*.jsonl"))
    with beta.open("a", encoding="utf-8") as f:
        f.write("\n")
    assert export.run_export(db, [claude_dir]).files_parsed == 1
    assert calls == [str(beta)]


def test_rows_survive_transcript_deletion(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    shutil.rmtree(claude_dir / "projects" / "C--work-beta")
    result = export.run_export(db, [claude_dir])
    assert result.messages == 4
    assert _rows(db, "SELECT COUNT(*) FROM sessions WHERE id = '22222222'") == [(1,)]


def test_duplicate_reply_across_files_counts_once(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    assert _rows(db, "SELECT COUNT(*) FROM messages WHERE key LIKE 'm1:%'") == [(1,)]
    assert _rows(db, "SELECT COUNT(*) FROM events WHERE kind = 'tool' AND name = 'Read'") == [
        (1,)
    ]


def test_folded_file_does_not_blank_title(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    # The subagent file changes and is re-parsed alone; its FileParse has no title.
    sub = next(claude_dir.rglob("agent-explore.jsonl"))
    with sub.open("a", encoding="utf-8") as f:
        f.write("\n")
    assert export.run_export(db, [claude_dir]).files_parsed == 1
    assert _rows(db, "SELECT title, cwd FROM sessions WHERE id = '11111111'") == [
        ("Alpha work", "/work/alpha")
    ]


def test_version_mismatch_backs_up_and_rebuilds(
    claude_dir: Path, db: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    export.run_export(db, [claude_dir])
    with sqlite3.connect(db) as conn:
        conn.execute("PRAGMA user_version = 99")
        conn.execute("INSERT INTO sessions (id) VALUES ('gone')")
    capsys.readouterr()
    export.run_export(db, [claude_dir])
    assert "rebuilt" in capsys.readouterr().out
    assert _rows(db, "PRAGMA user_version") == [(store.SCHEMA_VERSION,)]
    assert _rows(db, "SELECT COUNT(*) FROM sessions WHERE id = 'gone'") == [(0,)]
    backup = db.with_name("usage.db.bak.v99")
    assert _rows(backup, "SELECT COUNT(*) FROM sessions") == [(3,)]


def test_second_schema_change_keeps_first_backup(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    for old, marker in ((97, "first"), (98, "second")):
        with sqlite3.connect(db) as conn:
            conn.execute(f"PRAGMA user_version = {old}")
            conn.execute("INSERT INTO sessions (id) VALUES (?)", (marker,))
        export.run_export(db, [claude_dir])
    for old, marker in ((97, "first"), (98, "second")):
        backup = db.with_name(f"usage.db.bak.v{old}")
        assert _rows(backup, f"SELECT id FROM sessions WHERE id = '{marker}'") == [
            (marker,)
        ]


def test_concurrent_export_raises_export_busy(
    claude_dir: Path,
    db: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    export.run_export(db, [claude_dir])
    holder = sqlite3.connect(db, isolation_level=None)
    holder.execute("BEGIN IMMEDIATE")
    try:
        with pytest.raises(store.ExportBusy):
            export.run_export(db, [claude_dir], timeout=0.1)
        monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(db.parent))
        monkeypatch.setattr(store, "LOCK_TIMEOUT", 0.1)
        assert cli.main(["export", "--claude-dir", str(claude_dir)]) == 0
        assert "export already running" in capsys.readouterr().out
    finally:
        holder.execute("ROLLBACK")
        holder.close()


def test_cli_export_prints_counts(
    claude_dir: Path,
    db: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(db.parent))
    assert cli.main(["export", "--claude-dir", str(claude_dir)]) == 0
    out = capsys.readouterr().out
    assert "files scanned 3, files parsed 3, messages 4, events 10" in out
    assert store.store_path() == db


@pytest.mark.parametrize("before_command", [True, False])
def test_cli_export_keeps_claude_dir_in_either_position(
    before_command: bool,
    claude_dir: Path,
    db: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(db.parent))
    empty = tmp_path / "default-claude"
    empty.mkdir()
    monkeypatch.setenv("C4_CLAUDE_DIR", str(empty))  # what a dropped flag falls back to
    flag = ["--claude-dir", str(claude_dir)]
    argv = [*flag, "export"] if before_command else ["export", *flag]
    assert cli.main(argv) == 0
    assert "files scanned 3," in capsys.readouterr().out


def test_partial_copy_of_a_reply_does_not_shrink_it(claude_dir: Path, db: Path) -> None:
    export.run_export(db, [claude_dir])
    # A later fork holding a mid-stream copy of reply m1 (50 output tokens when final).
    fork = claude_dir / "projects" / "C--work-beta" / "33333333-cccc-0000-0000-000000000000.jsonl"
    fork.write_text(
        '{"type":"assistant","uuid":"c-copy","requestId":"r1",'
        '"timestamp":"2026-10-01T09:01:05Z","message":{"id":"m1",'
        '"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":5}}}\n',
        encoding="utf-8",
    )
    export.run_export(db, [claude_dir])
    assert _rows(db, "SELECT output FROM messages WHERE key LIKE 'm1:%'") == [(50,)]
