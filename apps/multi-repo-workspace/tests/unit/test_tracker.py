"""tracker: sidecar lifecycle edges, defensive reads, startup reset."""

from __future__ import annotations

import json

import pytest

from roundtable import tracker


def test_missing_sidecar_reads_ready(project):
    rec = tracker.read_record(project, "x")
    assert rec == {"slug": "x", "status": "ready", "history": []}


def test_corrupt_sidecar_reads_ready(project):
    path = tracker.sidecar_path(project, "x")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{not json", encoding="utf-8")
    assert tracker.read_record(project, "x")["status"] == "ready"


def test_unrecognised_status_defensively_ready(project):
    path = tracker.sidecar_path(project, "x")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"status": "exploded"}), encoding="utf-8")
    rec = tracker.read_record(project, "x")
    assert rec["status"] == "ready"
    assert rec["slug"] == "x" and rec["history"] == []


def test_manual_edges_roundtrip(project):
    rec = tracker.set_status(project, "x", "implemented", trigger="manual")
    assert rec["status"] == "implemented"
    rec = tracker.set_status(project, "x", "ready", trigger="manual")
    assert rec["status"] == "ready"
    hist = rec["history"]
    assert [(h["from"], h["to"], h["trigger"]) for h in hist] == [
        ("ready", "implemented", "manual"),
        ("implemented", "ready", "manual"),
    ]
    assert all(h["ts"].endswith("Z") for h in hist)


def test_round_edges_with_run_id_and_rc(project):
    tracker.set_status(project, "x", "running", trigger="round", run_id="ord_1")
    rec = tracker.set_status(
        project, "x", "implemented", trigger="round", run_id="ord_1", rc=0
    )
    assert rec["history"][-1] == {
        "ts": rec["history"][-1]["ts"],
        "from": "running",
        "to": "implemented",
        "trigger": "round",
        "run_id": "ord_1",
        "rc": 0,
    }


def test_illegal_edge_rejected(project):
    tracker.set_status(project, "x", "implemented", trigger="manual")
    with pytest.raises(ValueError, match="illegal transition"):
        tracker.set_status(project, "x", "running", trigger="round")


def test_same_status_edge_rejected(project):
    with pytest.raises(ValueError, match="illegal transition"):
        tracker.set_status(project, "x", "ready", trigger="manual")


def test_disallowed_trigger_rejected(project):
    with pytest.raises(ValueError, match="not allowed"):
        tracker.set_status(project, "x", "implemented", trigger="startup_reset")


def test_reset_stale_runs(project):
    tracker.set_status(project, "a", "running", trigger="round")
    tracker.set_status(project, "b/c", "running", trigger="round")
    tracker.set_status(project, "done", "implemented", trigger="manual")
    reset = tracker.reset_stale_runs([project])
    assert sorted(reset) == [("repo", "a"), ("repo", "b/c")]
    assert tracker.read_record(project, "a")["status"] == "ready"
    assert (
        tracker.read_record(project, "a")["history"][-1]["trigger"] == "startup_reset"
    )
    assert tracker.read_record(project, "done")["status"] == "implemented"


def test_reset_stale_runs_no_impl_dir(project):
    assert tracker.reset_stale_runs([project]) == []
