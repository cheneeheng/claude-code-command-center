"""White-box tests for server branches not reachable over a clean socket:
SSE keepalive/multiline framing, client-disconnect handling, and run_server()."""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from docket import core, server, tracker
from tests.conftest import write_plan


class FakeWfile:
    def __init__(self, raise_on=None):
        self.data = b""
        self._n = 0
        self._raise_on = raise_on

    def write(self, b):
        self._n += 1
        if self._raise_on is not None and self._n >= self._raise_on:
            raise BrokenPipeError("client gone")
        self.data += b

    def flush(self):
        pass


def _handler(wfile, manager=None, registry_path=None):
    h = server.Handler.__new__(server.Handler)
    h.wfile = wfile
    h.request_version = "HTTP/1.1"
    h.requestline = "GET / HTTP/1.1"  # accessed by send_response -> log_request
    h.command = "GET"
    h.server = SimpleNamespace(manager=manager, registry_path=registry_path)
    return h


# --- SSE framing (keepalive + multiline data + end) ---------------------------


def test_api_stream_frames_keepalive_multiline_and_end():
    events = iter([("keepalive", None), ("data", "first\nsecond"), ("end", "done")])
    manager = SimpleNamespace(stream=lambda rid: events)
    wfile = FakeWfile()
    _handler(wfile, manager)._api_stream({"run_id": ["x"]})
    out = wfile.data
    assert b": keep-alive\n\n" in out
    assert b"data: first\ndata: second\n\n" in out
    assert b"event: end\ndata: done\n\n" in out


def test_api_stream_client_disconnect_is_swallowed():
    events = iter([("data", "a"), ("data", "b"), ("data", "c")])
    manager = SimpleNamespace(stream=lambda rid: events)
    # raise on the first body write (after headers already flushed)
    wfile = FakeWfile(raise_on=2)
    # must not propagate
    _handler(wfile, manager)._api_stream({"run_id": ["x"]})


def test_do_get_broken_pipe_is_swallowed():
    wfile = FakeWfile(raise_on=1)  # blow up while flushing index.html headers
    h = _handler(wfile)
    h.path = "/"
    h.do_GET()  # BrokenPipeError caught, no raise


# --- _api_stop branches -------------------------------------------------------


def test_api_stop_success():
    manager = SimpleNamespace(stop=lambda rid: None)
    wfile = FakeWfile()
    _handler(wfile, manager)._api_stop({"run_id": "x"})
    assert b'"ok": true' in wfile.data


def test_api_stop_not_stoppable_is_409():
    def stop(rid):
        raise ValueError("run x is 'done', not stoppable")

    manager = SimpleNamespace(stop=stop)
    wfile = FakeWfile()
    _handler(wfile, manager)._api_stop({"run_id": "x"})
    assert b"409" in wfile.data.split(b"\r\n")[0]
    assert b"not stoppable" in wfile.data


# --- run_server lifecycle -----------------------------------------------------


class FakeHTTPD:
    instances: list["FakeHTTPD"] = []

    def __init__(self, addr, handler):
        self.addr = addr
        self.handler = handler
        self.closed = False
        FakeHTTPD.instances.append(self)

    def serve_forever(self):
        raise KeyboardInterrupt  # simulate Ctrl-C immediately

    def server_close(self):
        self.closed = True


@pytest.fixture
def fake_httpd(monkeypatch):
    FakeHTTPD.instances.clear()
    monkeypatch.setattr(server, "ThreadingHTTPServer", FakeHTTPD)
    return FakeHTTPD


def test_run_server_with_projects_and_stale_reset(
    fake_httpd, project, tmp_path, capsys
):
    write_plan(project, "alpha")
    tracker.set_status(project, "alpha", "running", trigger="headless")  # stale
    reg = tmp_path / "projects.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "repo", "path": project.path}]}),
        encoding="utf-8",
    )
    rc = server.run_server(port=0, registry=str(reg))
    assert rc == 0
    assert fake_httpd.instances[0].closed
    out = capsys.readouterr().out
    assert "reset 1 stale run(s)" in out
    assert "shutting down" in out


def test_run_server_port_falls_back_to_config(fake_httpd, project, tmp_path):
    reg = tmp_path / ".docket.json"
    reg.write_text(
        json.dumps(
            {"port": 9111, "projects": [{"name": "repo", "path": project.path}]}
        ),
        encoding="utf-8",
    )
    server.run_server(port=None, registry=str(reg))  # no --port -> Config.port
    assert fake_httpd.instances[0].addr == ("127.0.0.1", 9111)


def test_run_server_no_projects_prints_search_paths(
    fake_httpd, monkeypatch, tmp_path, capsys
):
    monkeypatch.chdir(tmp_path)  # no ./projects.json
    monkeypatch.setattr(
        core.os.path, "expanduser", lambda p: p.replace("~", str(tmp_path))
    )
    rc = server.run_server(port=0, registry=None)
    assert rc == 0
    out = capsys.readouterr().out
    assert "no projects" in out
