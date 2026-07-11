"""Edge-branch coverage: cases too narrow for the main suites."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from roundtable import plans, registry, sessions
from roundtable.executor import Executor
from roundtable.rounds import RoundStore
from roundtable.sessions import SessionManager, _Live
from tests.conftest import ev_init, ev_result, write_plan
from tests.unit.test_sessions import wait_for


# --- plans: a directory named *.md must not be treated as a plan ------------------


def test_md_named_directory_skipped(project):
    (Path(project.path) / project.planning_dir / "adir.md").mkdir()
    write_plan(project, "real")
    assert [p.slug for p in plans.list_plans(project)] == ["real"]
    assert set(plans.snapshot(project)) == {"real"}


# --- registry: read_json retry + merge name collision ------------------------------


def test_read_json_retries_then_succeeds(tmp_path, monkeypatch):
    target = tmp_path / "f.json"
    target.write_text('{"ok": 1}', encoding="utf-8")
    real = Path.read_text
    calls = {"n": 0}

    def flaky(self, *a, **k):
        calls["n"] += 1
        if calls["n"] < 3:
            raise PermissionError("mid-replace")
        return real(self, *a, **k)

    monkeypatch.setattr(Path, "read_text", flaky)
    monkeypatch.setattr(registry.time, "sleep", lambda s: None)
    assert registry.read_json(target) == {"ok": 1}


def test_read_json_final_attempt_succeeds(tmp_path, monkeypatch):
    target = tmp_path / "f.json"
    target.write_text('{"ok": 1}', encoding="utf-8")
    real = Path.read_text
    calls = {"n": 0}

    def flaky(self, *a, **k):
        calls["n"] += 1
        if calls["n"] < 10:  # all 9 retry attempts fail; the final attempt succeeds
            raise PermissionError("mid-replace")
        return real(self, *a, **k)

    monkeypatch.setattr(Path, "read_text", flaky)
    monkeypatch.setattr(registry.time, "sleep", lambda s: None)
    assert registry.read_json(target) == {"ok": 1}


def test_read_json_persistent_failure_propagates(tmp_path, monkeypatch):
    target = tmp_path / "f.json"
    target.write_text("{}", encoding="utf-8")

    def always(self, *a, **k):
        raise PermissionError("locked hard")

    monkeypatch.setattr(Path, "read_text", always)
    monkeypatch.setattr(registry.time, "sleep", lambda s: None)
    with pytest.raises(PermissionError):
        registry.read_json(target)


def test_cmd_init_merge_collides_with_existing_name(tmp_path, monkeypatch):
    from tests.unit.test_registry import _mkrepo

    monkeypatch.chdir(tmp_path)
    _mkrepo(tmp_path / "x", "proj")
    registry.cmd_init(scan=str(tmp_path / "x"))
    _mkrepo(tmp_path / "y", "proj")  # same name, different path
    registry.cmd_init(scan=str(tmp_path / "y"), merge=True)
    data = json.loads((tmp_path / ".roundtable.json").read_text(encoding="utf-8"))
    assert sorted(p["name"] for p in data["projects"]) == ["proj", "proj-2"]


# --- rounds: lookup misses + recover with already-terminal orders -------------------


def test_find_order_miss_with_populated_round(state_dir, project):
    store = RoundStore(state_dir)
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    with pytest.raises(KeyError):
        store.find_order("ord_ghost")


def test_set_instruction_unknown_order(state_dir, project):
    store = RoundStore(state_dir)
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    with pytest.raises(KeyError):
        store.set_instruction("ord_ghost", "x")


def test_recover_leaves_terminal_orders(state_dir, project):
    store = RoundStore(state_dir)
    write_plan(project, "alpha")
    write_plan(project, "beta")
    oid = store.add_order(project, "alpha", None)["id"]
    store.add_order(project, "beta", None)
    rnd = store.end_turn({project.name: project})
    store.order_running(rnd["id"], oid)
    store.order_terminal(rnd["id"], oid, "succeeded", rc=0)
    assert store.recover() is True  # beta was queued -> skipped; alpha untouched
    states = {o["slug"]: o["state"] for o in store.get(rnd["id"])["orders"]}
    assert states == {"alpha": "succeeded", "beta": "skipped"}


# --- executor: skip with no live feed + blank stream lines -------------------------


def test_skip_without_live_entry(state_dir, project):
    store = RoundStore(state_dir)
    ex = Executor(store)
    write_plan(project, "alpha")
    oid = store.add_order(project, "alpha", None)["id"]
    rnd = store.end_turn({project.name: project})
    ex._skip(rnd["id"], oid, "no live feed")
    _, order = store.find_order(oid)
    assert order["state"] == "skipped"


def test_executor_skips_blank_stream_lines(
    state_dir, project, claude_on_path, fake_popen
):
    store = RoundStore(state_dir)
    ex = Executor(store)
    fake_popen(["", "   ", ev_result()])
    write_plan(project, "alpha")
    store.add_order(project, "alpha", None)
    rnd = store.end_turn({project.name: project})
    ex.start({project.name: project}, rnd)
    assert wait_for(lambda: store.get(rnd["id"])["status"] == "review")


# --- sessions: narrow branches ------------------------------------------------------


@pytest.fixture
def mgr(state_dir) -> SessionManager:
    return SessionManager(state_dir)


def test_format_parsed_unknown_block_type():
    ev = {"type": "assistant", "message": {"content": [{"type": "thinking"}]}}
    assert sessions.format_parsed(ev) == []


def test_live_push_reaches_subscriber_and_follow(
    mgr, project, claude_on_path, fake_popen
):
    cap = fake_popen([ev_init()], hang=True)
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    live = mgr._live[sid]
    gen = mgr.attach(sid, keepalive=5)
    next(gen)  # the buffered user line
    live.push({"kind": "text", "text": "late line"})  # push AFTER attach
    assert next(gen) == ("data", {"kind": "text", "text": "late line"})
    cap["proc"].stdout.release()
    items = list(gen)
    assert items[-1][0] == "end"


def test_get_skips_blank_and_non_dict_transcript_lines(
    mgr, project, claude_on_path, fake_popen
):
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    mgr._append_raw(sid, "")
    mgr._append_raw(sid, "[1, 2]")
    transcript = mgr.get(sid)["transcript"]
    assert all(e["text"] != "[1, 2]" for e in transcript)


def test_get_without_transcript_file(mgr):
    mgr._save(
        {
            "id": "ps_bare",
            "project": "repo",
            "claude_session_id": None,
            "status": "idle",
            "created_at": "2026-01-01T00:00:00Z",
            "turns": [],
            "cost_est_usd": None,
            "produced_plans": [],
        }
    )
    assert mgr.get("ps_bare")["transcript"] == []


def test_stop_with_no_live_entry(mgr):
    mgr._save(
        {
            "id": "ps_x",
            "project": "repo",
            "claude_session_id": None,
            "status": "streaming",
            "created_at": "2026-01-01T00:00:00Z",
            "turns": [],
            "cost_est_usd": None,
            "produced_plans": [],
        }
    )
    mgr.stop("ps_x")  # no live turn: only the stopped marker is appended
    assert any(
        e["kind"] == "status" and e["text"] == "[stopped]"
        for e in mgr.get("ps_x")["transcript"]
    )


def test_stop_with_live_but_no_proc(mgr):
    mgr._save(
        {
            "id": "ps_y",
            "project": "repo",
            "claude_session_id": None,
            "status": "streaming",
            "created_at": "2026-01-01T00:00:00Z",
            "turns": [],
            "cost_est_usd": None,
            "produced_plans": [],
        }
    )
    mgr._live["ps_y"] = _Live()  # turn thread has not spawned the process yet
    mgr.stop("ps_y")
    assert mgr._live["ps_y"].stopping is True


def test_recover_skips_non_streaming(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    assert mgr.recover() == 0


def test_turn_skips_blank_stdout_lines(mgr, project, claude_on_path, fake_popen):
    fake_popen(["", "  ", ev_result()])
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")


def test_resume_init_does_not_overwrite_session_id(
    mgr, project, claude_on_path, fake_popen
):
    fake_popen([ev_init("sid-first"), ev_result()])
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    fake_popen([ev_init("sid-second"), ev_result()])
    mgr.message(project, sid, "again")
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    assert mgr.meta(sid)["claude_session_id"] == "sid-first"


def test_produced_plan_not_duplicated_across_turns(
    mgr, project, claude_on_path, fake_popen
):
    cap = fake_popen([ev_init(), ev_result()], hang=True)
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    write_plan(project, "same-slug")
    cap["proc"].stdout.release()
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    cap2 = fake_popen([ev_result()], hang=True)
    mgr.message(project, sid, "tweak it")
    assert wait_for(lambda: cap2.get("proc") is not None)
    write_plan(project, "same-slug", "# changed again\n")
    cap2["proc"].stdout.release()
    assert wait_for(lambda: mgr.meta(sid)["status"] == "idle")
    assert mgr.meta(sid)["produced_plans"] == [{"slug": "same-slug", "turn": 1}]
