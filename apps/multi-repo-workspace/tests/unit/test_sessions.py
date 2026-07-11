"""sessions: planning-session manager against a fake claude (canned stream-json)."""

from __future__ import annotations

import json
import subprocess
import time

import pytest

from roundtable import locks, sessions
from roundtable.locks import Conflict
from roundtable.sessions import SessionManager
from tests.conftest import USAGE, ev_init, ev_result, ev_text, ev_tool, write_plan


def wait_for(cond, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if cond():
            return True
        time.sleep(0.01)
    return False


@pytest.fixture
def mgr(state_dir) -> SessionManager:
    return SessionManager(state_dir)


def wait_idle(mgr, sid, status=("idle",)):
    assert wait_for(lambda: mgr.meta(sid)["status"] in status), (
        f"session never reached {status}: {mgr.meta(sid)['status']}"
    )


# --- helpers -------------------------------------------------------------------


def test_new_id_prefix_and_url_safety():
    sid = sessions.new_id("ps")
    assert sid.startswith("ps_") and len(sid) > 10
    assert "/" not in sid and "+" not in sid


def test_resolve_bin_on_path(monkeypatch):
    monkeypatch.setattr(sessions.shutil, "which", lambda b: "/usr/bin/claude")
    assert sessions.resolve_bin("claude") == "claude"


def test_resolve_bin_explicit_file(monkeypatch, tmp_path):
    monkeypatch.setattr(sessions.shutil, "which", lambda b: None)
    exe = tmp_path / "claude.exe"
    exe.write_text("", encoding="utf-8")
    assert sessions.resolve_bin(str(exe)) == str(exe)


def test_resolve_bin_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(sessions.shutil, "which", lambda b: None)
    assert sessions.resolve_bin(str(tmp_path / "nope")) is None


def test_build_claude_cmd_flags(project, claude_on_path):
    project.model = "claude-opus-4-8"
    project.claude_extra_args = ["--fallback-model", "x"]
    cmd = sessions.build_claude_cmd(project, "plan")
    assert cmd is not None
    assert cmd[1:3] == ["-p", "--output-format"]
    assert "--permission-mode" in cmd and "plan" in cmd
    assert "--model" in cmd and "claude-opus-4-8" in cmd
    assert cmd[-2:] == ["--fallback-model", "x"]
    assert "--allowedTools" in cmd


def test_build_claude_cmd_missing_bin(project, monkeypatch):
    monkeypatch.setattr(sessions.shutil, "which", lambda b: None)
    assert sessions.build_claude_cmd(project, "plan") is None


def test_spawn_claude_real_process(tmp_path):
    import sys

    proc = sessions.spawn_claude(
        [sys.executable, "-c", "import sys; print('got:' + sys.stdin.read())"],
        cwd=str(tmp_path),
        prompt="hello",
    )
    assert proc.stdout is not None
    out = proc.stdout.read()
    proc.wait()
    assert "got:hello" in out and proc.returncode == 0


def test_stop_process_graceful():
    class P:
        def __init__(self):
            self.terminated = self.killed = False

        def terminate(self):
            self.terminated = True

        def wait(self, timeout=None):
            return 0

        def kill(self):
            self.killed = True

    p = P()
    sessions.stop_process(p)  # type: ignore[arg-type]
    assert p.terminated and not p.killed


def test_stop_process_kills_after_grace():
    class P:
        def __init__(self):
            self.killed = False

        def terminate(self):
            pass

        def wait(self, timeout=None):
            raise subprocess.TimeoutExpired(cmd="claude", timeout=timeout)

        def kill(self):
            self.killed = True

    p = P()
    sessions.stop_process(p, grace=0.01)  # type: ignore[arg-type]
    assert p.killed


# --- format_event / format_parsed ---------------------------------------------


def test_format_text_and_tool():
    items = sessions.format_event(ev_text("hello"))
    assert items == [{"kind": "text", "text": "hello"}]
    items = sessions.format_event(ev_tool("Write", "a.md"))
    assert items == [{"kind": "tool", "text": "▸ Write a.md"}]


def test_format_tool_without_digest():
    ev = json.dumps(
        {
            "type": "assistant",
            "message": {"content": [{"type": "tool_use", "name": "T", "input": {}}]},
        }
    )
    assert sessions.format_event(ev) == [{"kind": "tool", "text": "▸ T"}]


def test_tool_digest_first_line_and_non_str():
    assert sessions._tool_digest({"command": "ls\nrm -rf"}) == "ls"
    assert sessions._tool_digest({"file_path": 42, "pattern": "x"}) == "x"
    assert sessions._tool_digest({"command": ""}) == ""


def test_format_result_success_and_error():
    assert sessions.format_event(ev_result()) == [{"kind": "status", "text": "[done]"}]
    err = json.dumps({"type": "result", "subtype": "error_max_turns"})
    assert sessions.format_event(err) == [
        {"kind": "status", "text": "[error] error_max_turns"}
    ]
    is_err = json.dumps({"type": "result", "is_error": True, "subtype": "success"})
    assert sessions.format_event(is_err)[0]["text"].startswith("[error]")


def test_format_skips_empty_text_and_unknown():
    assert sessions.format_event(ev_text("   ")) == []
    assert sessions.format_event(json.dumps({"type": "system"})) == []
    assert sessions.format_event("") == []
    assert sessions.format_event("[1, 2]") == []


def test_format_non_json_passthrough():
    assert sessions.format_event("plain text\n") == [
        {"kind": "text", "text": "plain text"}
    ]


# --- lifecycle -----------------------------------------------------------------


def test_create_runs_first_turn(mgr, project, claude_on_path, fake_popen):
    cap = fake_popen(
        [
            ev_init("sid-abc"),
            ev_text("thinking"),
            ev_result(cost=0.08, usage=USAGE),
        ]
    )
    meta = mgr.create(project, "plan the thing")
    sid = meta["id"]
    assert meta["status"] == "streaming"
    wait_idle(mgr, sid)
    meta = mgr.meta(sid)
    assert meta["claude_session_id"] == "sid-abc"
    assert len(meta["turns"]) == 1
    turn = meta["turns"][0]
    assert turn["n"] == 1
    assert turn["cost_reported_usd"] == 0.08
    # no --model knob: the init event's model is the cost fallback (known -> estimate)
    assert meta["cost_est_usd"] > 0
    # turn-1 prompt is the planning template with {request}/{planning_dir} filled
    prompt = cap["proc"].stdin.written
    assert "plan the thing" in prompt and project.planning_dir in prompt
    assert cap["proc"].stdin.closed
    assert cap["kwargs"]["cwd"] == project.path


def test_cost_estimate_with_known_model(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_init(model="claude-sonnet-4-5"), ev_result(usage=USAGE)])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    meta = mgr.meta(sid)
    assert meta["turns"][0]["cost_est_usd"] > 0
    assert meta["cost_est_usd"] == meta["turns"][0]["cost_est_usd"]


def test_produced_plan_detection(mgr, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init(), ev_result()], hang=True)
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    write_plan(project, "the-new-plan")  # Claude "writes" the plan mid-turn
    cap["proc"].stdout.release()
    wait_idle(mgr, sid)
    assert mgr.meta(sid)["produced_plans"] == [{"slug": "the-new-plan", "turn": 1}]


def test_message_resume_and_streaming_conflict(
    mgr, project, claude_on_path, fake_popen
):
    fake_popen([ev_init("sid-1"), ev_result()])
    sid = mgr.create(project, "first")["id"]
    wait_idle(mgr, sid)

    cap2 = fake_popen([ev_result()], hang=True)
    mgr.message(project, sid, "follow up")
    assert wait_for(lambda: cap2.get("proc") is not None)
    assert "--resume" in cap2["cmd"] and "sid-1" in cap2["cmd"]
    assert cap2["proc"].stdin.written == "follow up"  # raw message, no re-wrapping
    with pytest.raises(Conflict):  # one in-flight turn per session
        mgr.message(project, sid, "again")
    cap2["proc"].stdout.release()
    wait_idle(mgr, sid)
    # duplicate slugs are not re-appended; second turn recorded
    assert [t["n"] for t in mgr.meta(sid)["turns"]] == [1, 2]


def test_stop_mid_turn(mgr, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init()], hang=True)
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    mgr.stop(sid)
    assert cap["proc"].terminated
    wait_idle(mgr, sid)
    transcript = mgr.get(sid)["transcript"]
    assert {"n": 1, "kind": "status", "text": "[stopped]"} in transcript


def test_stop_requires_streaming(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    with pytest.raises(Conflict):
        mgr.stop(sid)


def test_close_and_terminal_states(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    assert mgr.close(sid)["status"] == "closed"
    with pytest.raises(Conflict):
        mgr.message(project, sid, "too late")
    with pytest.raises(Conflict):
        mgr.close(sid)


def test_repo_busy_flips_back_to_idle(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_result()])
    locks.acquire(project.path, "an implement run")
    try:
        sid = mgr.create(project, "x")["id"]
        wait_idle(mgr, sid)
        meta = mgr.meta(sid)
        assert meta["turns"] == []  # no turn ran
    finally:
        locks.release(project.path)


def test_missing_claude_bin_fails_session(mgr, project, fake_popen, monkeypatch):
    fake_popen([ev_result()])
    monkeypatch.setattr(sessions.shutil, "which", lambda b: None)
    project.claude_bin = "definitely-not-here"
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid, status=("failed",))


def test_spawn_oserror_fails_session(mgr, project, claude_on_path, fake_popen):
    fake_popen([], side_effect=OSError("exec format error"))
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid, status=("failed",))


def test_nonzero_rc_without_result_fails(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_init()], returncode=1)
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid, status=("failed",))


def test_nonzero_rc_with_result_is_valid_turn(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_result(subtype="error_during_execution")], returncode=1)
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)  # a model refusal is still a valid turn


def test_non_json_and_non_dict_stream_lines(mgr, project, claude_on_path, fake_popen):
    fake_popen(["garbage line", "[1,2]", ev_result()])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    texts = [e["text"] for e in mgr.get(sid)["transcript"]]
    assert "garbage line" in texts


def test_recover_marks_interrupted(mgr, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init()], hang=True)
    sid = mgr.create(project, "x")["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    # simulate a process death: meta on disk still says streaming
    fresh = SessionManager(mgr._dir.parent)
    assert fresh.recover() == 1
    assert fresh.meta(sid)["status"] == "idle"
    assert {"n": 1, "kind": "status", "text": "[interrupted]"} in fresh.get(sid)[
        "transcript"
    ]
    cap["proc"].stdout.release()  # let the orphan thread finish
    assert wait_for(lambda: not locks.is_held(project.path))


def test_recover_nothing_to_do(mgr):
    assert mgr.recover() == 0


# --- queries ---------------------------------------------------------------------


def test_list_sessions_empty_and_filtered(mgr, project, claude_on_path, fake_popen):
    assert mgr.list_sessions() == []
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    assert [m["id"] for m in mgr.list_sessions("repo")] == [sid]
    assert mgr.list_sessions("other") == []
    assert mgr.streaming_count("repo") == 0


def test_meta_unknown_session(mgr):
    with pytest.raises(KeyError):
        mgr.meta("ps_ghost")


def test_get_renders_transcript_kinds(mgr, project, claude_on_path, fake_popen):
    fake_popen([ev_init(), ev_text("answer"), ev_tool(), ev_result()])
    sid = mgr.create(project, "ask")["id"]
    wait_idle(mgr, sid)
    mgr._append_raw(sid, "raw non-json")
    kinds = [(e["kind"], e["n"]) for e in mgr.get(sid)["transcript"]]
    assert ("user", 1) in kinds and ("text", 1) in kinds and ("tool", 1) in kinds
    assert ("text", 1) in kinds  # the raw passthrough line


# --- SSE attach --------------------------------------------------------------------


def test_attach_not_streaming_ends_immediately(
    mgr, project, claude_on_path, fake_popen
):
    fake_popen([ev_result()])
    sid = mgr.create(project, "x")["id"]
    wait_idle(mgr, sid)
    assert list(mgr.attach(sid)) == [("end", "idle")]


def test_attach_replays_buffer_then_follows(mgr, project, claude_on_path, fake_popen):
    cap = fake_popen([ev_init(), ev_text("early")], hang=True)
    sid = mgr.create(project, "x")["id"]
    live = mgr._live[sid]
    assert wait_for(lambda: any(i.get("text") == "early" for i in live.buffer))
    gen = mgr.attach(sid, keepalive=0.05)
    first = next(gen)
    assert first[0] == "data" and first[1]["kind"] == "user"
    second = next(gen)
    assert second[1]["text"] == "early"
    third = next(gen)  # nothing new yet -> keepalive ping
    assert third == ("keepalive", None)
    cap["proc"].stdout.release()
    rest = list(gen)
    assert rest[-1][0] == "end"
