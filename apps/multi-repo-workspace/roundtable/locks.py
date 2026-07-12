"""Per-project locks shared by planning sessions, the executor, file save, and commit.

Intra-process only (documented MVP limitation, docket precedent): a planning turn and
an implement run on one repo can never interleave within this server process.
"""

from __future__ import annotations

import threading

_locks: dict[str, threading.Lock] = {}
_holders: dict[str, str] = {}
_guard = threading.Lock()

# Process-wide lock serializing round number assignment + round file read-modify-write.
rounds_lock = threading.Lock()


class Conflict(Exception):
    """A state conflict the API reports as 409: carries the error code + detail."""

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


def project_lock(path: str) -> threading.Lock:
    """The per-project lock for PATH (created on first use)."""
    with _guard:
        return _locks.setdefault(path, threading.Lock())


def try_acquire(path: str, holder: str) -> bool:
    """Non-blocking acquire; records HOLDER for the UI's busy hint on success."""
    if not project_lock(path).acquire(blocking=False):
        return False
    _holders[path] = holder
    return True


def acquire(path: str, holder: str) -> None:
    """Blocking acquire (executor orders wait for a streaming planning turn)."""
    project_lock(path).acquire()
    _holders[path] = holder


def release(path: str) -> None:
    _holders.pop(path, None)
    project_lock(path).release()


def holder(path: str) -> str | None:
    """Who currently holds the repo, or None. Display hint only — never a guard."""
    return _holders.get(path) if project_lock(path).locked() else None


def is_held(path: str) -> bool:
    return project_lock(path).locked()
