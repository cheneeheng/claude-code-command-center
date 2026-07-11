"""locks: per-project lock table + holder hints."""

from __future__ import annotations

import threading

from roundtable import locks


def test_try_acquire_and_release():
    assert locks.try_acquire("/p", "task a")
    assert locks.is_held("/p")
    assert locks.holder("/p") == "task a"
    assert not locks.try_acquire("/p", "task b")
    locks.release("/p")
    assert not locks.is_held("/p")
    assert locks.holder("/p") is None


def test_blocking_acquire_waits():
    locks.acquire("/p", "first")
    done = threading.Event()

    def second():
        locks.acquire("/p", "second")
        done.set()

    t = threading.Thread(target=second, daemon=True)
    t.start()
    assert not done.wait(timeout=0.1)
    locks.release("/p")
    assert done.wait(timeout=5)
    assert locks.holder("/p") == "second"
    locks.release("/p")


def test_holder_none_when_unlocked():
    assert locks.holder("/never-locked") is None


def test_conflict_carries_code_and_detail():
    exc = locks.Conflict("repo_busy", "busy right now")
    assert exc.code == "repo_busy"
    assert exc.detail == "busy right now"
    assert str(exc) == "busy right now"
