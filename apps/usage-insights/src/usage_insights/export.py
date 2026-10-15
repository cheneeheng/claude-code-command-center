"""Incremental export of Claude Code transcripts into the store.

Rows are upserted, never deleted, so history outlives Claude Code's transcript
cleanup and a reply copied into several files counts once.
"""

from __future__ import annotations

import os
import sqlite3
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from claude_usage import FileParse, parse_file, transcript_files

from usage_insights import store

PROGRESS_EVERY = 100


@dataclass(frozen=True)
class ExportResult:
    """What one export run did.

    Attributes:
        files_scanned: Transcript files found.
        files_parsed: Files re-parsed because they were new or changed.
        messages: Message rows in the store after the run.
        events: Event rows in the store after the run.
    """

    files_scanned: int
    files_parsed: int
    messages: int
    events: int


def _iso(ts: datetime | None) -> str | None:
    return ts.isoformat() if ts is not None else None


def _write(conn: sqlite3.Connection, fp: FileParse) -> None:
    """Upsert one parsed file's session, messages, and events."""
    execute = conn.execute
    execute(
        "INSERT INTO sessions (id, project, title, cwd) VALUES (?, ?, ?, ?) "
        "ON CONFLICT (id) DO UPDATE SET "
        "title = COALESCE(excluded.title, sessions.title), "
        "cwd = COALESCE(excluded.cwd, sessions.cwd)",
        (fp.session_id, fp.project, fp.title, fp.cwd),
    )
    for m in fp.messages:
        # session_id is not updated: a reply stays with the session that saw it first.
        # A copy with fewer output tokens is a mid-stream snapshot (a fork made while the
        # reply streamed), so it never replaces the stored counts.
        execute(
            "INSERT INTO messages (key, session_id, model, ts, input, output, "
            "cache_write, cache_read, cache_write_1h) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT (key) DO UPDATE SET model = excluded.model, ts = excluded.ts, "
            "input = excluded.input, output = excluded.output, "
            "cache_write = excluded.cache_write, cache_read = excluded.cache_read, "
            "cache_write_1h = excluded.cache_write_1h "
            "WHERE excluded.output >= messages.output",
            (
                m.key, m.session_id, m.model, _iso(m.ts), m.input, m.output,
                m.cache_write, m.cache_read, m.cache_write_1h,
            ),
        )
    for e in fp.events:
        execute(
            "INSERT INTO events (key, kind, name, ts, session_id) VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT (key) DO NOTHING",
            (e.key, e.kind, e.name, _iso(e.ts), e.session_id),
        )


def run_export(
    db: Path,
    dirs: list[Path] | None = None,
    timeout: float | None = None,
    progress: Callable[[str], None] = print,
) -> ExportResult:
    """Export new and changed transcripts into the store at ``db``.

    Args:
        db: The store file. Its directory is created when missing.
        dirs: Claude config dirs to read. Defaults to ``claude_usage.claude_dirs``.
        timeout: Seconds to wait for another writer. Defaults to
            :data:`store.LOCK_TIMEOUT`.
        progress: Receives progress and warning lines.

    Returns:
        The run's :class:`ExportResult`.

    Raises:
        store.ExportBusy: Another export holds the write lock.
    """
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = store.connect(db, timeout)
    try:
        backup = store.backup_if_stale(conn, db)
        store.begin_write(conn)
        store.ensure_schema(conn)
        if backup:
            progress(
                f"store schema changed: old store copied to {backup.name} and rebuilt "
                "from transcripts on disk; rows for deleted transcripts are lost"
            )
        known = {
            path: (size, mtime)
            for path, size, mtime in conn.execute("SELECT path, size, mtime_ns FROM files")
        }
        files = transcript_files(dirs)
        parsed = 0
        now = datetime.now(UTC).isoformat()
        for path in files:
            st = os.stat(path)
            if known.get(path) == (st.st_size, st.st_mtime_ns):
                continue
            fp = parse_file(path)
            _write(conn, fp)
            conn.execute(
                "INSERT INTO files (path, size, mtime_ns, exported_at) VALUES (?, ?, ?, ?) "
                "ON CONFLICT (path) DO UPDATE SET size = excluded.size, "
                "mtime_ns = excluded.mtime_ns, exported_at = excluded.exported_at",
                (path, st.st_size, st.st_mtime_ns, now),
            )
            parsed += 1
            if parsed % PROGRESS_EVERY == 0:
                progress(f"parsed {parsed} files...")
        if parsed:
            # One grouped pass: an upserted reply can move another session's span.
            conn.execute(
                "UPDATE sessions SET started = span.lo, ended = span.hi FROM ("
                "SELECT session_id, MIN(ts) AS lo, MAX(ts) AS hi FROM messages "
                "GROUP BY session_id) AS span WHERE sessions.id = span.session_id"
            )
        conn.execute(
            "INSERT INTO meta (key, value) VALUES ('last_export', ?) "
            "ON CONFLICT (key) DO UPDATE SET value = excluded.value",
            (now,),
        )
        messages = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
        events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        conn.execute("COMMIT")
    finally:
        if conn.in_transaction:
            conn.execute("ROLLBACK")
        conn.close()
    return ExportResult(len(files), parsed, messages, events)
