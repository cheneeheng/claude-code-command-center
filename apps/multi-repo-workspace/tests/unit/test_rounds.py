"""rounds: store, state machines, orders, review mutations, close/carry-over."""

from __future__ import annotations

import json

import pytest

from roundtable import tracker
from roundtable.locks import Conflict
from roundtable.registry import atomic_write_json
from roundtable.rounds import RoundStore
from tests.conftest import write_plan


@pytest.fixture
def store(state_dir) -> RoundStore:
    return RoundStore(state_dir)


@pytest.fixture
def ready_plan(project) -> str:
    write_plan(project, "alpha")
    return "alpha"


def add(store, project, slug="alpha", instruction=None):
    return store.add_order(project, slug, instruction)


def run_all(store, project, states=("succeeded",)):
    """Drive the current round's orders to terminal states via the store."""
    rnd = store.end_turn({project.name: project})
    for order, state in zip(rnd["orders"], states):
        store.order_running(rnd["id"], order["id"])
        store.order_terminal(rnd["id"], order["id"], state, rc=0, cost_est_usd=0.5)
    store.maybe_finish(rnd["id"])
    return store.get(rnd["id"])


def test_first_boot_creates_round_one(store):
    rnd = store.current()
    assert rnd["number"] == 1 and rnd["status"] == "open"
    assert rnd["orders"] == [] and rnd["carried_followups"] == []
    assert rnd["id"].startswith("rnd_")
    assert store.current()["id"] == rnd["id"]  # stable across calls


def test_invariant_two_open_rounds(store, state_dir):
    store.current()
    rogue = store._new_round(number=99, carried=[])
    atomic_write_json(store._path(rogue["id"]), rogue)
    with pytest.raises(Conflict, match="non-done rounds"):
        store.current()


def test_get_unknown_round(store):
    with pytest.raises(KeyError):
        store.get("rnd_ghost")


def test_add_order_happy_and_duplicate(store, project, ready_plan):
    order = add(store, project)
    assert order["id"].startswith("ord_")
    assert order["state"] == "queued" and order["reviewed"] is False
    with pytest.raises(Conflict, match="already in this round"):
        add(store, project)


def test_add_order_missing_plan(store, project):
    with pytest.raises(FileNotFoundError):
        add(store, project, "ghost")


def test_add_order_bad_slug(store, project):
    with pytest.raises(ValueError):
        add(store, project, "../escape")


def test_add_order_not_ready(store, project, ready_plan):
    tracker.set_status(project, ready_plan, "implemented", trigger="manual")
    with pytest.raises(Conflict, match="not runnable"):
        add(store, project)


def test_add_order_requires_open(store, project, ready_plan):
    add(store, project)
    store.end_turn({project.name: project})
    write_plan(project, "beta")
    with pytest.raises(Conflict, match="not open"):
        add(store, project, "beta")


def test_remove_order(store, project, ready_plan):
    oid = add(store, project)["id"]
    store.remove_order(oid)
    assert store.current()["orders"] == []
    with pytest.raises(KeyError):
        store.remove_order(oid)


def test_remove_order_requires_open(store, project, ready_plan):
    oid = add(store, project)["id"]
    store.end_turn({project.name: project})
    with pytest.raises(Conflict, match="not open"):
        store.remove_order(oid)


def test_set_instruction_and_clear(store, project, ready_plan):
    oid = add(store, project)["id"]
    assert store.set_instruction(oid, "do it")["instruction"] == "do it"
    assert store.set_instruction(oid, "")["instruction"] is None
    store.end_turn({project.name: project})
    with pytest.raises(Conflict, match="not open"):
        store.set_instruction(oid, "late")


def test_end_turn_requires_orders_and_open(store, project):
    with pytest.raises(ValueError, match="no orders"):
        store.end_turn({})
    write_plan(project, "alpha")
    add(store, project)
    store.end_turn({project.name: project})
    with pytest.raises(Conflict, match="not open"):
        store.end_turn({project.name: project})


def test_end_turn_skips_stale_orders(store, project, ready_plan):
    add(store, project)
    write_plan(project, "beta")
    add(store, project, "beta")
    tracker.set_status(project, "beta", "implemented", trigger="manual")  # goes stale
    rnd = store.end_turn({project.name: project})
    states = {o["slug"]: o["state"] for o in rnd["orders"]}
    assert states == {"alpha": "queued", "beta": "skipped"}
    assert any(
        "not ready" in ln for ln in store.read_output(rnd["id"], rnd["orders"][1]["id"])
    )


def test_end_turn_unknown_project_skipped(store, project, ready_plan):
    add(store, project)
    rnd = store.end_turn({})  # project vanished from the registry
    assert rnd["orders"][0]["state"] == "skipped"


def test_order_transitions_validated(store, project, ready_plan):
    oid = add(store, project)["id"]
    rnd = store.end_turn({project.name: project})
    with pytest.raises(Conflict):
        store.order_terminal(rnd["id"], oid, "succeeded")  # queued -> succeeded illegal
    store.order_running(rnd["id"], oid)
    store.order_terminal(rnd["id"], oid, "failed", rc=2)
    _, order = store.find_order(oid)
    assert order["state"] == "failed" and order["rc"] == 2
    with pytest.raises(Conflict):
        store.order_running(rnd["id"], oid)  # terminal is terminal


def test_find_order_unknown(store):
    with pytest.raises(KeyError):
        store.find_order("ord_ghost")


def test_maybe_finish_paths(store, project, ready_plan):
    rid = store.current()["id"]
    assert store.maybe_finish(rid) is False  # not executing
    oid = add(store, project)["id"]
    write_plan(project, "beta")
    oid2 = add(store, project, "beta")["id"]
    store.end_turn({project.name: project})
    store.order_running(rid, oid)
    store.order_terminal(rid, oid, "succeeded", rc=0)
    assert store.maybe_finish(rid) is False  # beta still queued
    store.order_running(rid, oid2)
    store.order_terminal(rid, oid2, "succeeded", rc=0)
    assert store.maybe_finish(rid) is True
    assert store.get(rid)["status"] == "review"


def test_stop_drains_queued(store, project, ready_plan):
    add(store, project)
    with pytest.raises(Conflict, match="not executing"):
        store.stop()
    store.end_turn({project.name: project})
    rnd = store.stop()
    assert rnd["status"] == "review"
    assert rnd["orders"][0]["state"] == "skipped"


def test_recover_paths(store, project, ready_plan):
    assert store.recover() is False
    oid = add(store, project)["id"]
    write_plan(project, "beta")
    add(store, project, "beta")
    rnd = store.end_turn({project.name: project})
    store.order_running(rnd["id"], oid)
    assert store.recover() is True
    rec = store.get(rnd["id"])
    assert rec["status"] == "review"
    states = {o["slug"]: o["state"] for o in rec["orders"]}
    assert states == {"alpha": "stopped", "beta": "skipped"}


def test_cost_rollup_computed_at_read_time(store, project, ready_plan, state_dir):
    add(store, project)
    rnd = run_all(store, project)
    assert rnd["cost_est_usd"] == 0.5
    raw = json.loads(store._path(rnd["id"]).read_text(encoding="utf-8"))
    assert "cost_est_usd" not in raw  # never stored


def test_cost_rollup_null_when_no_costs(store):
    assert store.current()["cost_est_usd"] is None


def test_review_mutations_and_phase_guard(store, project, ready_plan):
    oid = add(store, project)["id"]
    with pytest.raises(Conflict, match="not review"):
        store.set_reviewed(oid, True)
    run_all(store, project)
    assert store.set_reviewed(oid, True)["reviewed"] is True
    assert store.set_followup(oid, "  tighten tests  ")["followup"] == "tighten tests"
    assert store.set_followup(oid, "   ")["followup"] is None
    with pytest.raises(ValueError, match="exceeds"):
        store.set_followup(oid, "x" * 3000)


def test_close_carries_followups(store, project, ready_plan):
    oid = add(store, project)["id"]
    run_all(store, project)
    store.set_followup(oid, "next: docs")
    nxt = store.close()
    assert nxt["number"] == 2 and nxt["status"] == "open"
    assert nxt["carried_followups"] == [
        {"from_round": 1, "project": "repo", "slug": "alpha", "note": "next: docs"}
    ]


def test_close_requires_review(store):
    with pytest.raises(Conflict):
        store.close()


def test_unaddressed_carried_rolls_forward(store, project, ready_plan):
    oid = add(store, project)["id"]
    run_all(store, project)
    store.set_followup(oid, "note-a")
    store.close()
    # round 2: alpha's carry-over is NOT re-ordered; a new beta order gets a note
    write_plan(project, "beta")
    oid2 = add(store, project, "beta")["id"]
    rnd2 = store.end_turn({project.name: project})
    store.order_running(rnd2["id"], oid2)
    store.order_terminal(rnd2["id"], oid2, "succeeded", rc=0)
    store.maybe_finish(rnd2["id"])
    store.set_followup(oid2, "note-b")
    rnd3 = store.close()
    notes = {(c["project"], c["slug"]): c["note"] for c in rnd3["carried_followups"]}
    assert notes == {("repo", "beta"): "note-b", ("repo", "alpha"): "note-a"}


def test_addressed_carried_is_dropped(store, project, ready_plan):
    oid = add(store, project)["id"]
    run_all(store, project)
    store.set_followup(oid, "again")
    store.close()
    # round 2 re-orders alpha (addressing the carry-over), no new note
    oid2 = add(store, project)["id"]
    rnd2 = store.end_turn({project.name: project})
    store.order_running(rnd2["id"], oid2)
    store.order_terminal(rnd2["id"], oid2, "succeeded", rc=0)
    store.maybe_finish(rnd2["id"])
    assert store.close()["carried_followups"] == []


def test_dismiss_followup(store, project, ready_plan):
    oid = add(store, project)["id"]
    run_all(store, project)
    store.set_followup(oid, "to dismiss")
    store.close()
    with pytest.raises(KeyError):
        store.dismiss_followup(5)
    store.dismiss_followup(0)
    assert store.current()["carried_followups"] == []


def test_dismiss_requires_open(store, project, ready_plan):
    add(store, project)
    store.end_turn({project.name: project})
    with pytest.raises(Conflict, match="not open"):
        store.dismiss_followup(0)


def test_list_rounds_newest_first(store, project, ready_plan):
    oid = add(store, project)["id"]
    run_all(store, project)
    store.set_reviewed(oid, True)
    store.close()
    rounds = store.list_rounds()
    assert [r["number"] for r in rounds] == [2, 1]


def test_read_output_missing_and_malformed(store):
    assert store.read_output("rnd_x", "ord_x") == []
    store.append_output("rnd_x", "ord_x", "good line")
    path = store.output_path("rnd_x", "ord_x")
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("not json\n\n" + json.dumps({"noline": 1}) + "\n")
    assert store.read_output("rnd_x", "ord_x") == [
        "good line",
        "not json",
        '{"noline": 1}',
    ]
