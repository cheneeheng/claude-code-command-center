"""executor: End-Turn batch runner against the fake claude."""

from __future__ import annotations

import threading

import pytest

from roundtable import locks, tracker
from roundtable.executor import Executor, resolve_instruction
from roundtable.rounds import RoundStore
from tests.conftest import USAGE, ev_init, ev_result, ev_text, write_plan
from tests.unit.test_sessions import wait_for


@pytest.fixture
def store(state_dir) -> RoundStore:
    return RoundStore(state_dir)


@pytest.fixture
def ex(store) -> Executor:
    return Executor(store)


def queue_orders(store, project, slugs=("alpha",)):
    for slug in slugs:
        write_plan(project, slug)
        store.add_order(project, slug, None)
    return store.end_turn({project.name: project})


def wait_review(store, rid, timeout=10.0):
    assert wait_for(lambda: store.get(rid)["status"] == "review", timeout), (
        f"round stuck: {store.get(rid)}"
    )
    return store.get(rid)


def test_resolve_instruction_paths(project):
    out = resolve_instruction(project, "a/b", None)
    assert f"{project.planning_dir}/a/b.md" in out
    assert resolve_instruction(project, "a", "just do X") == "just do X"
    assert resolve_instruction(project, "a", "read {path} now").endswith("a.md now")


def test_all_orders_skipped_finishes_round(store, ex, project):
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    tracker.set_status(project, "alpha", "implemented", trigger="manual")
    rnd = store.end_turn({project.name: project})  # skips the stale order
    ex.start({project.name: project}, rnd)
    assert store.get(rnd["id"])["status"] == "review"


def test_success_run(store, ex, project, claude_on_path, fake_popen):
    cap = fake_popen(
        [ev_init(model="claude-sonnet-4-5"), ev_text("working"), ev_result(usage=USAGE)]
    )
    rnd = queue_orders(store, project)
    ex.start({project.name: project}, rnd)
    rec = wait_review(store, rnd["id"])
    order = rec["orders"][0]
    assert order["state"] == "succeeded" and order["rc"] == 0
    assert order["cost_est_usd"] > 0 and order["cost_reported_usd"] == 0.05
    assert tracker.read_record(project, "alpha")["status"] == "implemented"
    hist = tracker.read_record(project, "alpha")["history"]
    assert [(h["from"], h["to"]) for h in hist] == [
        ("ready", "running"),
        ("running", "implemented"),
    ]
    assert hist[-1]["run_id"] == order["id"]
    lines = store.read_output(rnd["id"], order["id"])
    assert "working" in lines and any("run completed" in ln for ln in lines)
    # instruction on stdin names the plan file; body never piped
    assert f"{project.planning_dir}/alpha.md" in cap["proc"].stdin.written


def test_failure_skips_rest_of_project(store, ex, project, claude_on_path, fake_popen):
    fake_popen([ev_init(), ev_result(subtype="error")], returncode=3)
    rnd = queue_orders(store, project, ("alpha", "beta"))
    ex.start({project.name: project}, rnd)
    rec = wait_review(store, rnd["id"])
    states = {o["slug"]: o["state"] for o in rec["orders"]}
    assert states == {"alpha": "failed", "beta": "skipped"}
    assert tracker.read_record(project, "alpha")["status"] == "ready"
    assert tracker.read_record(project, "beta")["status"] == "ready"
    failed = next(o for o in rec["orders"] if o["slug"] == "alpha")
    assert failed["rc"] == 3
    lines = store.read_output(rnd["id"], failed["id"])
    assert any("run failed (rc=3)" in ln for ln in lines)


def test_missing_claude_bin_fails_without_tracker_touch(
    store, ex, project, fake_popen, monkeypatch
):
    import roundtable.sessions as sessions

    fake_popen([ev_result()])
    monkeypatch.setattr(sessions.shutil, "which", lambda b: None)
    rnd = queue_orders(store, project)
    ex.start({project.name: project}, rnd)
    rec = wait_review(store, rnd["id"])
    assert rec["orders"][0]["state"] == "failed"
    assert tracker.read_record(project, "alpha")["history"] == []  # never ran


def test_spawn_oserror_resets_tracker(store, ex, project, claude_on_path, fake_popen):
    fake_popen([], side_effect=OSError("bad exec"))
    rnd = queue_orders(store, project)
    ex.start({project.name: project}, rnd)
    rec = wait_review(store, rnd["id"])
    assert rec["orders"][0]["state"] == "failed"
    assert tracker.read_record(project, "alpha")["status"] == "ready"


def test_stop_terminates_inflight(store, ex, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init()], hang=True)
    rnd = queue_orders(store, project, ("alpha", "beta"))
    ex.start({project.name: project}, rnd)
    assert wait_for(lambda: cap.get("proc") is not None)
    ex.stop()
    rec = wait_review(store, rnd["id"])
    states = {o["slug"]: o["state"] for o in rec["orders"]}
    assert states["alpha"] == "stopped"
    assert states["beta"] == "skipped"
    assert cap["procs"][0].terminated
    assert tracker.read_record(project, "alpha")["status"] == "ready"


def test_waits_for_repo_lock(store, ex, project, claude_on_path, fake_popen):
    fake_popen([ev_result()])
    locks.acquire(project.path, "a planning turn")
    rnd = queue_orders(store, project)
    ex.start({project.name: project}, rnd)
    oid = rnd["orders"][0]["id"]
    assert wait_for(
        lambda: any(
            "waiting for repo" in ln for ln in store.read_output(rnd["id"], oid)
        )
    )
    assert store.get(rnd["id"])["status"] == "executing"
    locks.release(project.path)
    rec = wait_review(store, rnd["id"])
    assert rec["orders"][0]["state"] == "succeeded"


def test_concurrent_across_projects(
    store, ex, project, tmp_path, claude_on_path, fake_popen
):
    from roundtable.registry import Project

    other_root = tmp_path / "other"
    (other_root / ".agents_workspace" / "planning").mkdir(parents=True)
    other = Project(name="other", path=str(other_root))
    fake_popen([ev_result()])
    write_plan(project, "alpha")
    write_plan(other, "gamma")
    store.add_order(project, "alpha", None)
    store.add_order(other, "gamma", None)
    rnd = store.end_turn({project.name: project, other.name: other})
    ex.start({project.name: project, other.name: other}, rnd)
    rec = wait_review(store, rnd["id"])
    assert all(o["state"] == "succeeded" for o in rec["orders"])


def test_attach_live_then_end(store, ex, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init(), ev_text("live line")], hang=True)
    rnd = queue_orders(store, project)
    oid = rnd["orders"][0]["id"]
    ex.start({project.name: project}, rnd)
    assert wait_for(lambda: ex._live.get(oid) is not None)
    assert wait_for(lambda: "live line" in ex._live[oid].buffer)
    gen = ex.attach(rnd["id"], oid, "running", keepalive=0.05)
    first = next(gen)
    assert first == ("data", "live line")
    assert next(gen) == ("keepalive", None)
    cap["proc"].stdout.release()
    items = list(gen)
    assert items[-1][0] == "end" and items[-1][1] == "succeeded"


def test_attach_replay_after_finish(store, ex, project, claude_on_path, fake_popen):
    fake_popen([ev_text("recorded"), ev_result()])
    rnd = queue_orders(store, project)
    oid = rnd["orders"][0]["id"]
    ex.start({project.name: project}, rnd)
    wait_review(store, rnd["id"])
    fresh = Executor(store)  # no live entry: replay from the file
    items = list(fresh.attach(rnd["id"], oid, "succeeded"))
    assert ("data", "recorded") in items
    assert items[-1] == ("end", "succeeded")


def test_order_state_unknown(ex):
    assert ex._order_state("ord_ghost") == "unknown"


def test_non_json_and_error_result_lines(
    store, ex, project, claude_on_path, fake_popen
):
    fake_popen(["plain stderr noise", "[1,2]", ev_result(subtype="error_max_turns")])
    rnd = queue_orders(store, project)
    ex.start({project.name: project}, rnd)
    rec = wait_review(store, rnd["id"])
    order = rec["orders"][0]
    assert order["state"] == "succeeded"  # rc 0 despite error subtype
    lines = store.read_output(rnd["id"], order["id"])
    assert "plain stderr noise" in lines
    assert any("[error] error_max_turns" in ln for ln in lines)


def test_settle_conflict_keeps_recorded_state(store, ex, project):
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    rnd = store.end_turn({project.name: project})
    oid = rnd["orders"][0]["id"]
    store.order_running(rnd["id"], oid)
    store.order_terminal(rnd["id"], oid, "stopped")  # settled elsewhere (stop race)
    from roundtable.executor import _OrderLive

    assert ex._settle(rnd["id"], oid, _OrderLive(), "failed") == "failed"
    _, order = store.find_order(oid)
    assert order["state"] == "stopped"  # the recorded state wins


def test_skip_conflict_returns_early(store, ex, project):
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    rnd = store.end_turn({project.name: project})
    oid = rnd["orders"][0]["id"]
    store.order_running(rnd["id"], oid)
    before = store.read_output(rnd["id"], oid)
    ex._skip(rnd["id"], oid, "reason")  # running -> skipped is illegal: no-op
    assert store.read_output(rnd["id"], oid) == before


def test_stop_before_first_order_runs(store, ex, project, claude_on_path, fake_popen):
    """_run_project_batch's self._stop branch: stop set before the batch starts."""
    fake_popen([ev_result()])
    rnd = queue_orders(store, project)
    ex._stop = True
    done = threading.Event()

    def run():
        ex._run_project_batch(project, rnd["id"], rnd["orders"])
        done.set()

    threading.Thread(target=run, daemon=True).start()
    assert done.wait(5)
    _, order = store.find_order(rnd["orders"][0]["id"])
    assert order["state"] == "skipped"
