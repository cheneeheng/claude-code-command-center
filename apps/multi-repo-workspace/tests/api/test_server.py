"""API tests: real HTTP against make_server (ephemeral port, temp state dir)."""

from __future__ import annotations

import http.client
import json
import threading
import time
from pathlib import Path

import pytest

from roundtable import gitinfo, locks, server, tracker
from roundtable.server import make_server
from tests.conftest import ev_init, ev_result, ev_text, write_plan
from tests.unit.test_sessions import wait_for


@pytest.fixture
def srv(gitrepo, registry_file, state_dir):
    httpd = make_server(0, registry_file, state_dir)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    port = httpd.server_address[1]

    class Client:
        base = f"127.0.0.1:{port}"
        app = httpd.app  # type: ignore[attr-defined]
        project = gitrepo
        state = state_dir

        def request(self, method, path, body=None, raw_body=None):
            conn = http.client.HTTPConnection(self.base, timeout=10)
            payload = (
                raw_body
                if raw_body is not None
                else (json.dumps(body).encode() if body is not None else None)
            )
            conn.request(method, path, body=payload)
            resp = conn.getresponse()
            data = resp.read()
            conn.close()
            ctype = resp.getheader("Content-Type", "")
            parsed = json.loads(data) if "application/json" in ctype else data
            return resp.status, parsed

        def get(self, path):
            return self.request("GET", path)

        def post(self, path, body=None, raw_body=None):
            return self.request("POST", path, body=body, raw_body=raw_body)

        def put(self, path, body=None):
            return self.request("PUT", path, body=body)

        def delete(self, path):
            return self.request("DELETE", path)

        def sse_lines(self, path, max_bytes=65536):
            conn = http.client.HTTPConnection(self.base, timeout=10)
            conn.request("GET", path)
            resp = conn.getresponse()
            assert resp.getheader("Content-Type") == "text/event-stream"
            data = resp.read(max_bytes)
            conn.close()
            return data.decode("utf-8")

    yield Client()
    httpd.shutdown()
    httpd.server_close()


# --- static + config + board ---------------------------------------------------


def test_index_and_static(srv):
    status, body = srv.get("/")
    assert status == 200 and b"roundtable" in body
    status, body = srv.get("/static/js/api.js")
    assert status == 200
    status, _ = srv.get("/static/nope.js")
    assert status == 404
    status, _ = srv.get("/static/../../pyproject.toml")
    assert status == 404


def test_api_config(srv):
    status, cfg = srv.get("/api/config")
    assert status == 200
    assert cfg["projects"][0]["name"] == "repo"
    assert len(cfg["registry_search_paths"]) >= 3


def test_api_board_real_state(srv):
    write_plan(srv.project, "alpha")
    status, board = srv.get("/api/board")
    assert status == 200
    card = board["projects"][0]
    assert card["state"]["branch"] == "main"
    assert card["git_error"] is None
    assert card["plans"] == {"ready": 1, "running": 0, "implemented": 0}
    assert card["sessions"] == {"streaming": 0}
    assert card["round"] is None
    assert board["round"]["number"] == 1 and board["round"]["status"] == "open"
    assert board["round"]["cost_est_usd"] is None
    assert board["last_done"] is None


def test_unknown_routes_404(srv):
    assert srv.get("/api/nope")[0] == 404
    assert srv.get("/api")[0] == 404
    assert srv.get("/nothing")[0] == 404
    assert srv.post("/api/repos/repo/unknown")[0] == 404
    assert srv.post("/api/sessions/ps_x/unknown")[0] == 404
    assert srv.post("/api/rounds/current/unknown")[0] == 404
    assert srv.post("/api/orders/ord_x/unknown")[0] == 404


def test_unknown_project_404(srv):
    status, err = srv.get("/api/repos/ghost/plans")
    assert status == 404 and err["error"] == "not_found"


def test_malformed_body_400(srv):
    status, err = srv.post("/api/sessions", raw_body=b"{not json")
    assert status == 400 and err["error"] == "bad_request"
    status, err = srv.post("/api/sessions", raw_body=b'"a string"')
    assert status == 400
    # unknown keys rejected (closed request shapes)
    status, err = srv.post("/api/repos/repo/commit", body={"message": "m", "extra": 1})
    assert status == 400 and "unknown key" in err["detail"]
    # missing required keys rejected
    status, err = srv.post("/api/repos/repo/commit", body={})
    assert status == 400 and "missing key" in err["detail"]
    # a file route with an unsupported verb falls through to 404
    assert srv.delete("/api/repos/repo/file?path=README.md")[0] == 404


def test_internal_error_500(srv, monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("kaboom")

    monkeypatch.setattr(gitinfo, "tree", boom)
    status, err = srv.get("/api/repos/repo/tree")
    assert status == 500 and err["error"] == "internal"


# --- repos -----------------------------------------------------------------------


def test_tree_and_file_read(srv):
    status, out = srv.get("/api/repos/repo/tree")
    assert status == 200
    assert any(e["name"] == "README.md" for e in out["entries"])
    status, out = srv.get("/api/repos/repo/file?path=README.md")
    assert status == 200 and out["content"].startswith("# fixture")
    assert srv.get("/api/repos/repo/file")[0] == 400  # path required
    assert srv.get("/api/repos/repo/file?path=../x")[0] == 400  # traversal
    assert srv.get("/api/repos/repo/file?path=ghost")[0] == 404


def test_file_binary_415_and_cap_413(srv, monkeypatch):
    root = Path(srv.project.path)
    (root / "bin.dat").write_bytes(b"\x00\x01")
    assert srv.get("/api/repos/repo/file?path=bin.dat")[0] == 415
    monkeypatch.setattr(gitinfo, "FILE_WRITE_CAP", 4)
    status, err = srv.put(
        "/api/repos/repo/file?path=big.txt",
        body={"content": "12345", "expect_mtime": None},
    )
    assert status == 413 and err["error"] == "too_large"


def test_file_save_roundtrip_and_stale(srv):
    status, out = srv.put(
        "/api/repos/repo/file?path=notes.md",
        body={"content": "# n\n", "expect_mtime": None},
    )
    assert status == 200
    mtime = out["mtime"]
    status, out = srv.put(
        "/api/repos/repo/file?path=notes.md",
        body={"content": "# n2\n", "expect_mtime": mtime},
    )
    assert status == 200 and out["mtime"] >= mtime
    status, err = srv.put(
        "/api/repos/repo/file?path=notes.md",
        body={"content": "x", "expect_mtime": 123},
    )
    assert status == 409 and err["error"] == "stale_file" and err["mtime"] > 0


def test_file_save_validation(srv):
    bad = [
        {"content": 42, "expect_mtime": None},
        {"content": "x", "expect_mtime": "soon"},
    ]
    for body in bad:
        assert srv.put("/api/repos/repo/file?path=a.txt", body=body)[0] == 400


def test_file_save_repo_busy(srv):
    locks.acquire(srv.project.path, "order ord_x")
    try:
        status, err = srv.put(
            "/api/repos/repo/file?path=a.txt",
            body={"content": "x", "expect_mtime": None},
        )
        assert status == 409 and err["error"] == "repo_busy"
        assert "ord_x" in err["detail"]
    finally:
        locks.release(srv.project.path)


def test_log_and_diff(srv):
    status, out = srv.get("/api/repos/repo/log?n=5")
    assert status == 200 and out["commits"][0]["subject"] == "init"
    (Path(srv.project.path) / "new.txt").write_text("n", encoding="utf-8")
    status, out = srv.get("/api/repos/repo/diff")
    assert status == 200 and out["untracked"] == ["new.txt"]


def test_git_error_500(srv, tmp_path, registry_file):
    # a registered project whose path is not a git repo -> log raises GitError
    plain = tmp_path / "plain"
    (plain / ".agents_workspace" / "planning").mkdir(parents=True)
    reg = json.loads(Path(registry_file).read_text(encoding="utf-8"))
    reg["projects"].append({"name": "plain", "path": str(plain)})
    Path(registry_file).write_text(json.dumps(reg), encoding="utf-8")
    status, err = srv.get("/api/repos/plain/log")
    assert status == 500 and err["error"] == "git_error"


def test_plans_list_detail_status(srv):
    write_plan(srv.project, "alpha", "---\ntitle: Alpha\n---\nbody\n")
    status, out = srv.get("/api/repos/repo/plans")
    assert status == 200
    assert out["plans"][0]["title"] == "Alpha"
    status, out = srv.get("/api/repos/repo/plans/alpha")
    assert status == 200
    assert out["title"] == "Alpha" and "claude -p" in out["manual_command"]
    # manual transition + illegal edge
    status, out = srv.post(
        "/api/repos/repo/plans/alpha/status", body={"to": "implemented"}
    )
    assert status == 200 and out["status"] == "implemented"
    status, err = srv.post(
        "/api/repos/repo/plans/alpha/status", body={"to": "implemented"}
    )
    assert status == 409 and err["error"] == "illegal_transition"
    # free-form status rejected; unknown plan 404
    assert (
        srv.post("/api/repos/repo/plans/alpha/status", body={"to": "exploded"})[0]
        == 400
    )
    assert (
        srv.post("/api/repos/repo/plans/ghost/status", body={"to": "ready"})[0] == 404
    )


def test_nested_plan_slug(srv):
    write_plan(srv.project, "v2/iter-01")
    status, out = srv.get("/api/repos/repo/plans/v2/iter-01")
    assert status == 200 and out["slug"] == "v2/iter-01"


def test_commit_route(srv):
    status, err = srv.post("/api/repos/repo/commit", body={"message": "   "})
    assert status == 400
    status, err = srv.post("/api/repos/repo/commit", body={"message": "m"})
    assert status == 409 and err["error"] == "nothing_to_commit"
    (Path(srv.project.path) / "c.txt").write_text("c", encoding="utf-8")
    locks.acquire(srv.project.path, "planning session ps_x")
    try:
        status, err = srv.post("/api/repos/repo/commit", body={"message": "m"})
        assert status == 409 and err["error"] == "repo_busy"
    finally:
        locks.release(srv.project.path)
    status, out = srv.post("/api/repos/repo/commit", body={"message": "add c"})
    assert status == 200 and out["subject"] == "add c"


# --- sessions ----------------------------------------------------------------------


def wait_session_idle(srv, sid):
    def idle():
        _, meta = srv.get(f"/api/sessions/{sid}")
        return meta["status"] in ("idle", "failed")

    assert wait_for(idle)


def test_session_flow(srv, claude_on_path, fake_popen):
    fake_popen([ev_init("sid-9"), ev_text("hi"), ev_result()])
    status, err = srv.post("/api/sessions", body={"project": "repo", "prompt": "  "})
    assert status == 400
    status, err = srv.post("/api/sessions", body={"project": "ghost", "prompt": "x"})
    assert status == 404
    status, meta = srv.post("/api/sessions", body={"project": "repo", "prompt": "go"})
    assert status == 201
    sid = meta["id"]
    wait_session_idle(srv, sid)
    status, listing = srv.get("/api/sessions?project=repo")
    assert status == 200 and listing["sessions"][0]["id"] == sid
    status, full = srv.get(f"/api/sessions/{sid}")
    assert full["claude_session_id"] == "sid-9"
    assert any(e["kind"] == "text" for e in full["transcript"])
    # SSE on an idle session ends immediately
    stream = srv.sse_lines(f"/api/sessions/{sid}/stream")
    assert "event: end" in stream and '"status": "idle"' in stream
    # follow-up turn, then stop guard, then close
    fake_popen([ev_result()])
    status, _ = srv.post(f"/api/sessions/{sid}/message", body={"prompt": "more"})
    assert status == 200
    wait_session_idle(srv, sid)
    status, err = srv.post(f"/api/sessions/{sid}/stop")
    assert status == 409  # not streaming
    assert srv.post(f"/api/sessions/{sid}/message", body={"prompt": " "})[0] == 400
    status, meta = srv.post(f"/api/sessions/{sid}/close")
    assert status == 200 and meta["status"] == "closed"
    assert srv.post(f"/api/sessions/{sid}/message", body={"prompt": "x"})[0] == 409
    assert srv.get("/api/sessions/ps_ghost")[0] == 404


def test_session_stop_midturn(srv, claude_on_path, fake_popen):
    cap = fake_popen([ev_init()], hang=True)
    status, meta = srv.post("/api/sessions", body={"project": "repo", "prompt": "go"})
    sid = meta["id"]
    assert wait_for(lambda: cap.get("proc") is not None)
    status, _ = srv.post(f"/api/sessions/{sid}/stop")
    assert status == 200
    wait_session_idle(srv, sid)
    status, board = srv.get("/api/board")
    assert status == 200, board
    assert board["projects"][0]["sessions"]["streaming"] == 0


def test_session_sse_live_stream(srv, claude_on_path, fake_popen, monkeypatch):
    cap = fake_popen([ev_init(), ev_text("streamed line")], hang=True)
    status, meta = srv.post("/api/sessions", body={"project": "repo", "prompt": "go"})
    sid = meta["id"]
    mgr = srv.app.sessions
    assert wait_for(
        lambda: (
            sid in mgr._live
            and any(i.get("text") == "streamed line" for i in mgr._live[sid].buffer)
        )
    )
    result = {}

    def reader():
        result["stream"] = srv.sse_lines(f"/api/sessions/{sid}/stream")

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    time.sleep(0.2)
    cap["proc"].stdout.release()
    t.join(timeout=10)
    assert "streamed line" in result["stream"]
    assert "event: end" in result["stream"]


def test_sse_keepalive_ping(srv, monkeypatch):
    """Cover _send_sse's keepalive branch without waiting 15s."""

    def fake_attach(sid):
        yield ("keepalive", None)
        yield ("end", "idle")

    monkeypatch.setattr(srv.app.sessions, "attach", fake_attach)
    stream = srv.sse_lines("/api/sessions/ps_any/stream")
    assert ": ping" in stream and "event: end" in stream


# --- rounds + orders -----------------------------------------------------------------


def test_round_and_order_flow(srv, claude_on_path, fake_popen):
    fake_popen([ev_init(), ev_text("run out"), ev_result()])
    write_plan(srv.project, "alpha")

    status, rnd = srv.get("/api/rounds/current")
    assert status == 200 and rnd["number"] == 1
    # guards before any orders exist
    assert srv.post("/api/rounds/current/end-turn")[0] == 400
    assert srv.post("/api/rounds/current/stop")[0] == 409
    assert srv.post("/api/rounds/current/close")[0] == 409
    assert srv.delete("/api/rounds/current/orders/ord_ghost")[0] == 404
    assert srv.get("/api/rounds/rnd_ghost")[0] == 404

    status, order = srv.post(
        "/api/rounds/current/orders", body={"project": "repo", "slug": "alpha"}
    )
    assert status == 201
    oid = order["id"]
    assert srv.post(f"/api/orders/{oid}/badaction")[0] == 404  # known order, bad verb
    # instruction override set and cleared
    status, out = srv.post(f"/api/orders/{oid}/instruction", body={"instruction": "X"})
    assert status == 200 and out["instruction"] == "X"
    assert srv.post(f"/api/orders/{oid}/instruction", body={"instruction": 7})[0] == 400
    status, out = srv.post(f"/api/orders/{oid}/instruction", body={"instruction": None})
    assert status == 200 and out["instruction"] is None
    # review mutations blocked while open
    assert srv.post(f"/api/orders/{oid}/reviewed", body={"reviewed": True})[0] == 409
    assert srv.post(f"/api/orders/{oid}/reviewed", body={"reviewed": "y"})[0] == 400

    status, rnd = srv.post("/api/rounds/current/end-turn")
    assert status == 200 and rnd["status"] == "executing"

    def in_review():
        return srv.get("/api/rounds/current")[1]["status"] == "review"

    assert wait_for(in_review, timeout=10)
    status, out = srv.get(f"/api/orders/{oid}/output")
    assert status == 200 and "run out" in out["lines"]
    assert out["state"] == "succeeded"
    stream = srv.sse_lines(f"/api/orders/{oid}/stream")
    assert "run out" in stream and "event: end" in stream

    # review + followup + close
    assert srv.post(f"/api/orders/{oid}/reviewed", body={"reviewed": True})[0] == 200
    assert srv.post(f"/api/orders/{oid}/followup", body={"note": "polish"})[0] == 200
    status, nxt = srv.post("/api/rounds/current/close")
    assert status == 200 and nxt["number"] == 2
    assert nxt["carried_followups"][0]["note"] == "polish"

    # history + board summary
    status, hist = srv.get("/api/rounds")
    assert status == 200 and [r["number"] for r in hist["rounds"]] == [2, 1]
    board = srv.get("/api/board")[1]
    assert board["last_done"]["succeeded"] == 1
    assert board["round"]["number"] == 2
    assert board["round"]["carried_followups"] == 1

    # dismiss the carried follow-up
    assert (
        srv.post("/api/rounds/current/followups/dismiss", body={"index": 5})[0] == 404
    )
    status, _ = srv.post("/api/rounds/current/followups/dismiss", body={"index": 0})
    assert status == 200
    assert srv.get("/api/rounds/current")[1]["carried_followups"] == []


def test_order_add_remove_and_board_round_chip(srv, claude_on_path):
    write_plan(srv.project, "alpha")
    status, order = srv.post(
        "/api/rounds/current/orders", body={"project": "repo", "slug": "alpha"}
    )
    assert status == 201
    board = srv.get("/api/board")[1]
    assert board["projects"][0]["round"] == {"orders": 1, "running": 0}
    status, _ = srv.delete(f"/api/rounds/current/orders/{order['id']}")
    assert status == 200
    assert srv.get("/api/rounds/current")[1]["orders"] == []


def test_round_stop_route(srv, claude_on_path, fake_popen):
    cap = fake_popen([ev_init()], hang=True)
    write_plan(srv.project, "alpha")
    srv.post("/api/rounds/current/orders", body={"project": "repo", "slug": "alpha"})
    srv.post("/api/rounds/current/end-turn")
    assert wait_for(lambda: cap.get("proc") is not None)
    assert wait_for(
        lambda: srv.get("/api/rounds/current")[1]["orders"][0]["state"] == "running"
    )
    board = srv.get("/api/board")[1]  # running order shows on the board round chip
    assert board["projects"][0]["round"] == {"orders": 1, "running": 1}
    status, rnd = srv.post("/api/rounds/current/stop")
    assert status == 200 and rnd["status"] == "review"
    assert wait_for(
        lambda: srv.get("/api/rounds/current")[1]["orders"][0]["state"] == "stopped"
    )


def test_order_add_conflicts(srv, claude_on_path):
    write_plan(srv.project, "alpha")
    tracker.set_status(srv.project, "alpha", "implemented", trigger="manual")
    status, err = srv.post(
        "/api/rounds/current/orders", body={"project": "repo", "slug": "alpha"}
    )
    assert status == 409 and err["error"] == "not_ready"
    status, err = srv.post(
        "/api/rounds/current/orders", body={"project": "repo", "slug": "ghost"}
    )
    assert status == 404


# --- startup recovery ------------------------------------------------------------------


def test_make_server_startup_recovery(gitrepo, registry_file, state_dir, capsys):
    write_plan(gitrepo, "alpha")
    tracker.set_status(gitrepo, "alpha", "running", trigger="round")
    # strand a streaming session meta + an executing round on disk
    from roundtable.rounds import RoundStore
    from roundtable.sessions import SessionManager

    mgr = SessionManager(state_dir)
    mgr._save(
        {
            "id": "ps_stuck",
            "project": "repo",
            "claude_session_id": None,
            "status": "streaming",
            "created_at": "2026-01-01T00:00:00Z",
            "turns": [],
            "cost_est_usd": None,
            "produced_plans": [],
        }
    )
    store = RoundStore(state_dir)
    rnd = store.current()
    from roundtable.registry import atomic_write_json

    rnd["status"] = "executing"
    rnd["orders"] = [
        {
            "id": "ord_stuck",
            "project": "repo",
            "slug": "alpha",
            "instruction": None,
            "state": "running",
            "rc": None,
            "usage": None,
            "cost_est_usd": None,
            "cost_reported_usd": None,
            "reviewed": False,
            "followup": None,
        }
    ]
    atomic_write_json(store._path(rnd["id"]), rnd)

    httpd = make_server(0, registry_file, state_dir)
    httpd.server_close()
    out = capsys.readouterr().out
    assert "reset 1 stale running sidecar" in out
    assert "marked 1 interrupted session" in out
    assert "moved an interrupted executing round" in out
    assert tracker.read_record(gitrepo, "alpha")["status"] == "ready"
    assert SessionManager(state_dir).meta("ps_stuck")["status"] == "idle"
    assert RoundStore(state_dir).get(rnd["id"])["status"] == "review"


def test_run_server_port_resolution_and_shutdown(
    registry_file, state_dir, monkeypatch, capsys
):
    """run_server: registry port fallback, empty-registry hint, Ctrl-C exit."""
    monkeypatch.setenv("C4_ROUNDTABLE_HOME", str(state_dir))

    class FakeHTTPD:
        def serve_forever(self):
            raise KeyboardInterrupt

        def server_close(self):
            pass

    seen = {}

    def fake_make(port, registry_path, state_dir=None):
        seen["port"] = port
        return FakeHTTPD()

    monkeypatch.setattr(server, "make_server", fake_make)
    assert server.run_server(port=None, registry_path=registry_file) == 0
    assert seen["port"] == 8640  # registry has no port key -> DEFAULT_PORT
    assert server.run_server(port=1234, registry_path=registry_file) == 0
    assert seen["port"] == 1234
    # empty registry prints the searched paths
    assert server.run_server(port=None, registry_path=None) == 0
    out = capsys.readouterr().out
    assert "no projects — searched:" in out
