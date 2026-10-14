"""The local SQLite store that keeps exported usage after transcripts are deleted."""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path

SCHEMA_VERSION = 1
# Seconds a writer waits for another writer before giving up with ExportBusy.
LOCK_TIMEOUT = 5.0

_TABLES = ("meta", "files", "sessions", "messages", "events")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY, size INTEGER, mtime_ns INTEGER, exported_at TEXT
);
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY, project TEXT, title TEXT, cwd TEXT, started TEXT, ended TEXT
);
CREATE TABLE IF NOT EXISTS messages (
    key TEXT PRIMARY KEY, session_id TEXT, model TEXT, ts TEXT, input INTEGER,
    output INTEGER, cache_write INTEGER, cache_read INTEGER, cache_write_1h INTEGER
);
CREATE TABLE IF NOT EXISTS events (
    key TEXT PRIMARY KEY, kind TEXT, name TEXT, ts TEXT, session_id TEXT
);
CREATE INDEX IF NOT EXISTS messages_ts ON messages (ts);
CREATE INDEX IF NOT EXISTS events_kind_ts ON events (kind, ts);
CREATE INDEX IF NOT EXISTS events_session_ts ON events (session_id, ts);
"""


class ExportBusy(Exception):
    """Another export holds the store's write lock."""


def store_path() -> Path:
    """Return the store file: ``$C4_USAGE_INSIGHTS_HOME/usage.db``.

    Defaults to ``~/.usage-insights/usage.db``.
    """
    home = os.environ.get("C4_USAGE_INSIGHTS_HOME")
    return (Path(home) if home else Path.home() / ".usage-insights") / "usage.db"


def connect(path: Path, timeout: float | None = None) -> sqlite3.Connection:
    """Open the store in WAL mode with explicit transaction control.

    WAL lets readers keep reading while an export writes.
    """
    conn = sqlite3.connect(
        path, timeout=LOCK_TIMEOUT if timeout is None else timeout, isolation_level=None
    )
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def begin_write(conn: sqlite3.Connection) -> None:
    """Take the write lock, or raise :class:`ExportBusy` when another writer has it."""
    try:
        conn.execute("BEGIN IMMEDIATE")
    except sqlite3.OperationalError as exc:
        if "locked" in str(exc) or "busy" in str(exc):
            raise ExportBusy from exc
        raise


def _stale(conn: sqlite3.Connection) -> bool:
    """Whether the store holds tables of another schema version."""
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    has_tables = conn.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'"
    ).fetchone()[0]
    return bool(has_tables) and version != SCHEMA_VERSION


def backup_if_stale(conn: sqlite3.Connection, path: Path) -> bool:
    """Copy a store of another schema version to ``usage.db.bak``.

    Must run before the write transaction: a backup cannot read through the same
    connection's open write lock.

    Returns:
        ``True`` when the store is stale, so :func:`ensure_schema` will rebuild it.
    """
    if not _stale(conn):
        return False
    backup = sqlite3.connect(path.with_name(path.name + ".bak"))
    try:
        conn.backup(backup)
    finally:
        backup.close()
    return True


def ensure_schema(conn: sqlite3.Connection) -> None:
    """Create the schema, dropping the tables of a stale store first.

    Must run inside the write transaction.
    """
    if _stale(conn):
        for table in _TABLES:
            conn.execute(f"DROP TABLE IF EXISTS {table}")
    for statement in _SCHEMA.split(";"):
        if statement.strip():
            conn.execute(statement)
    conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
