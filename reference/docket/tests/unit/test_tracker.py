"""Unit tests for the implementation sidecar tracker."""

import json

import pytest

from docket import tracker
from tests.conftest import write_plan


def test_sidecar_path_mirrors_slug(project):
    p = tracker.sidecar_path(project, "feature/ITER_01")
    assert p.as_posix().endswith(
        ".agents_workspace/implementation/feature/ITER_01.json"
    )


def test_read_record_missing_is_ready(project):
    rec = tracker.read_record(project, "ghost")
    assert rec == {"slug": "ghost", "status": "ready", "history": []}


def test_read_record_invalid_json_is_ready(project):
    path = tracker.sidecar_path(project, "broken")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{not json", encoding="utf-8")
    assert tracker.read_record(project, "broken")["status"] == "ready"


def test_read_record_unknown_status_defaults_ready(project):
    path = tracker.sidecar_path(project, "weird")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"status": "bogus"}), encoding="utf-8")
    rec = tracker.read_record(project, "weird")
    assert rec["status"] == "ready"
    assert rec["slug"] == "weird"
    assert rec["history"] == []


def test_set_status_manual_mark_and_history(project):
    rec = tracker.set_status(project, "alpha", "implemented", trigger="manual")
    assert rec["status"] == "implemented"
    assert rec["history"][-1]["from"] == "ready"
    assert rec["history"][-1]["to"] == "implemented"
    assert rec["history"][-1]["trigger"] == "manual"
    assert rec["history"][-1]["run_id"] is None
    assert rec["history"][-1]["rc"] is None
    assert rec["history"][-1]["ts"].endswith("Z")
    # persisted to disk
    assert tracker.read_record(project, "alpha")["status"] == "implemented"


def test_set_status_illegal_transition_raises(project):
    with pytest.raises(ValueError, match="illegal transition"):
        tracker.set_status(
            project, "alpha", "ready", trigger="manual"
        )  # (ready,ready) absent


def test_set_status_disallowed_trigger_raises(project):
    # ready->running is legal, but only for the 'headless' trigger.
    with pytest.raises(ValueError, match="not allowed"):
        tracker.set_status(project, "alpha", "running", trigger="manual")


def test_set_status_headless_running_then_implemented_records_rc(project):
    tracker.set_status(project, "alpha", "running", trigger="headless", run_id="r1")
    rec = tracker.set_status(
        project, "alpha", "implemented", trigger="headless", run_id="r1", rc=0
    )
    assert rec["history"][-1]["rc"] == 0
    assert rec["history"][-1]["run_id"] == "r1"


def test_atomic_write_retries_then_succeeds(project, monkeypatch):
    calls = {"n": 0}
    real_replace = tracker.os.replace

    def flaky_replace(src, dst):
        calls["n"] += 1
        if calls["n"] < 3:
            raise PermissionError("locked")
        return real_replace(src, dst)

    monkeypatch.setattr(tracker.os, "replace", flaky_replace)
    monkeypatch.setattr(tracker.time, "sleep", lambda *_: None)
    tracker.set_status(project, "alpha", "implemented", trigger="manual")
    assert calls["n"] == 3
    assert tracker.read_record(project, "alpha")["status"] == "implemented"


def test_atomic_write_gives_up_after_retries(project, monkeypatch):
    monkeypatch.setattr(
        tracker.os,
        "replace",
        lambda *_: (_ for _ in ()).throw(PermissionError("locked")),
    )
    monkeypatch.setattr(tracker.time, "sleep", lambda *_: None)
    with pytest.raises(PermissionError):
        tracker.set_status(project, "alpha", "implemented", trigger="manual")


def test_reset_stale_runs_no_impl_dir(project):
    assert tracker.reset_stale_runs([project]) == []


def test_reset_stale_runs_flips_running(project):
    write_plan(project, "alpha")
    tracker.set_status(project, "alpha", "running", trigger="headless")
    # a second, implemented plan must be left alone
    tracker.set_status(project, "beta", "implemented", trigger="manual")
    reset = tracker.reset_stale_runs([project])
    assert reset == [("repo", "alpha")]
    assert tracker.read_record(project, "alpha")["status"] == "ready"
    assert tracker.read_record(project, "beta")["status"] == "implemented"
    assert (
        tracker.read_record(project, "alpha")["history"][-1]["trigger"]
        == "startup_reset"
    )
