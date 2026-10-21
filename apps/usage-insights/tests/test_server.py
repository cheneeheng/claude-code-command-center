"""HTTP server and CLI: routes, Host check, refresh, bind behaviour."""

from __future__ import annotations

import json
import socket
import sqlite3
import threading
import urllib.error
import urllib.request
from collections.abc import Iterator
from pathlib import Path

import pytest

from usage_insights import cli, export, server


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture
def running(claude_dir: Path, db: Path, tmp_path: Path) -> Iterator[tuple[int, Path]]:
    """A served instance with an exported store and a stub frontend."""
    export.run_export(db, [claude_dir])
    static = tmp_path / "static"
    (static / "assets").mkdir(parents=True)
    (static / "index.html").write_text('<div id="root"></div>', encoding="utf-8")
    (static / "assets" / "app.js").write_text("console.log(1)", encoding="utf-8")
    port = _free_port()
    httpd = server.make_server("127.0.0.1", port, db, [claude_dir], static)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield port, static
    httpd.shutdown()
    httpd.server_close()


def _get(
    port: int,
    path: str,
    host: str | None = None,
    method: str = "GET",
    headers: dict[str, str] | None = None,
) -> tuple[int, bytes]:
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method=method)
    req.add_header("Host", host or f"127.0.0.1:{port}")
    for name, value in (headers or {}).items():
        req.add_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def test_server_smoke(running: tuple[int, Path], db: Path) -> None:
    port, _ = running
    assert _get(port, "/api/health") == (200, b'{"ok": true}')
    status, body = _get(port, "/api/summary?range=7d")
    assert status == 200
    assert json.loads(body)["range"] == "7d"
    assert _get(port, "/api/summary", host="evil.example")[0] == 403
    assert _get(port, "/api/summary", host=f"localhost:{port}")[0] == 200
    status, body = _get(port, "/api/summary?range=12m")
    assert status == 400 and "error" in json.loads(body)
    status, body = _get(port, "/api/refresh", method="POST")
    assert status == 200 and json.loads(body)["files_scanned"] == 3
    assert _get(port, "/nope")[0] == 404

    holder = sqlite3.connect(db, isolation_level=None)
    holder.execute("BEGIN IMMEDIATE")
    try:
        status, body = _get(port, "/api/refresh", method="POST")
        assert status == 409 and json.loads(body) == {"error": "export already running"}
    finally:
        holder.execute("ROLLBACK")
        holder.close()


def test_index_served_from_static(running: tuple[int, Path]) -> None:
    port, static = running
    assert _get(port, "/") == (200, b'<div id="root"></div>')
    assert _get(port, "/assets/app.js") == (200, b"console.log(1)")
    assert _get(port, "/assets/../index.html")[0] == 404
    (static / "index.html").unlink()
    status, body = _get(port, "/")
    assert status == 503 and b"frontend not built" in body


def test_cross_site_refresh_is_refused(running: tuple[int, Path]) -> None:
    port, _ = running
    for headers in ({"Origin": "http://evil.example"}, {"Sec-Fetch-Site": "cross-site"}):
        status, body = _get(port, "/api/refresh", method="POST", headers=headers)
        assert (status, json.loads(body)) == (403, {"error": "cross-site request"})
    own = {"Origin": f"http://127.0.0.1:{port}", "Sec-Fetch-Site": "same-origin"}
    assert _get(port, "/api/refresh", method="POST", headers=own)[0] == 200


def test_unreadable_store_gives_json_500(claude_dir: Path, tmp_path: Path) -> None:
    db = tmp_path / "usage.db"
    db.write_bytes(b"")  # created, but the first export never wrote the schema
    port = _free_port()
    httpd = server.make_server("127.0.0.1", port, db, [claude_dir], tmp_path)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        status, body = _get(port, "/api/summary")
        assert status == 500 and "no such table" in json.loads(body)["error"]
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_summary_without_store_is_empty(claude_dir: Path, tmp_path: Path) -> None:
    port = _free_port()
    httpd = server.make_server("127.0.0.1", port, tmp_path / "none" / "usage.db", [claude_dir], tmp_path)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        body = json.loads(_get(port, "/api/summary")[1])
        assert body["last_export"] is None
        assert body["sessions"] == [] and body["projection"]["pace"] == []
    finally:
        httpd.shutdown()
        httpd.server_close()


def _post(
    port: int,
    path: str,
    body: object,
    headers: dict[str, str] | None = None,
    method: str = "POST",
) -> tuple[int, bytes]:
    data = body if isinstance(body, bytes) else json.dumps(body).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method)
    req.add_header("Host", f"127.0.0.1:{port}")
    req.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        req.add_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def test_server_query_endpoint(running: tuple[int, Path]) -> None:
    port, _ = running
    spec = {"metric": "tokens", "group_by": "project", "range": "all"}
    status, body = _post(port, "/api/query?range=7d", spec)
    data = json.loads(body)
    assert status == 200 and data["range"] == "all"
    assert {r["key"] for r in data["rows"]} == {"alpha", "beta"}
    # Without its own range, a query follows the top bar's.
    status, body = _post(port, "/api/query?range=90d", {"metric": "sessions"})
    assert status == 200 and json.loads(body)["range"] == "90d"
    status, body = _post(port, "/api/query", {"metric": "dollars"})
    assert status == 400 and "metric" in json.loads(body)["error"]
    status, body = _post(port, "/api/query", spec, {"Sec-Fetch-Site": "cross-site"})
    assert (status, json.loads(body)) == (403, {"error": "cross-site request"})


LAYOUT = {"version": 1, "sections": [{"id": "s", "question": "Q?", "panels": [{"ref": "week"}]}]}


def test_layout_roundtrip_and_reset(running: tuple[int, Path], db: Path) -> None:
    port, _ = running
    assert _get(port, "/api/layout") == (204, b"")
    assert _post(port, "/api/layout", LAYOUT, method="PUT")[0] == 204
    status, body = _get(port, "/api/layout")
    assert status == 200 and json.loads(body) == LAYOUT
    assert (db.parent / "layout.json").is_file()
    assert _get(port, "/api/layout", method="DELETE")[0] == 204
    assert _get(port, "/api/layout") == (204, b"")
    assert _get(port, "/api/layout", method="DELETE")[0] == 204  # already gone: still fine
    cross = {"Sec-Fetch-Site": "cross-site"}
    assert _post(port, "/api/layout", LAYOUT, cross, method="PUT")[0] == 403
    assert _get(port, "/api/layout", method="DELETE", headers=cross)[0] == 403
    (db.parent / "layout.json").write_text("{half", encoding="utf-8")
    assert _get(port, "/api/layout") == (204, b"")  # a bad file falls back to the default


def test_layout_rejects_oversize_and_bad_shape(running: tuple[int, Path], db: Path) -> None:
    port, _ = running
    for bad in ([], {"version": 2, "sections": []}, {"version": 1, "sections": {}}, b"{nope"):
        status, body = _post(port, "/api/layout", bad, method="PUT")
        assert status == 400 and "error" in json.loads(body)
    big = {**LAYOUT, "pad": "x" * server.LAYOUT_MAX_BYTES}
    assert _post(port, "/api/layout", big, method="PUT")[0] == 400
    assert not (db.parent / "layout.json").exists()


def test_layout_write_is_atomic(
    running: tuple[int, Path], db: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    port, _ = running
    assert _post(port, "/api/layout", LAYOUT, method="PUT")[0] == 204
    assert sorted(p.name for p in db.parent.glob("layout.json*")) == ["layout.json"]
    replaced: list[tuple[str, str]] = []
    real = server.os.replace
    monkeypatch.setattr(
        server.os, "replace", lambda a, b: replaced.append((Path(a).name, Path(b).name)) or real(a, b)
    )
    assert _post(port, "/api/layout", LAYOUT, method="PUT")[0] == 204
    assert replaced == [("layout.json.tmp", "layout.json")]


def test_cli_exits_1_when_port_held(
    claude_dir: Path, db: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(db.parent))
    with socket.socket() as held:
        held.bind(("127.0.0.1", 0))
        held.listen()
        port = held.getsockname()[1]
        code = cli.main(["--no-open", "--port", str(port), "--claude-dir", str(claude_dir)])
    assert code == 1
    assert str(port) in capsys.readouterr().out


def test_cli_reuses_running_instance(
    running: tuple[int, Path], claude_dir: Path, db: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    port, _ = running
    monkeypatch.setenv("C4_USAGE_INSIGHTS_HOME", str(db.parent))
    opened: list[str] = []
    monkeypatch.setattr(cli.webbrowser, "open", opened.append)
    assert cli.main(["--port", str(port), "--claude-dir", str(claude_dir)]) == 0
    assert opened == [f"http://127.0.0.1:{port}/"]
