"""API tests: drive the real stdlib server over loopback HTTP."""

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import pytest

from docket import core, server
from tests.conftest import write_plan


@pytest.fixture
def live_server(project, tmp_path, monkeypatch):
    """A running ThreadingHTTPServer bound to an ephemeral loopback port."""
    write_plan(project, "alpha", "---\ntitle: Alpha\n---\n# body\n")
    reg = tmp_path / "projects.json"
    reg.write_text(
        json.dumps({"projects": [{"name": "repo", "path": project.path}]}),
        encoding="utf-8",
    )
    # never spawn a real claude during these tests
    monkeypatch.setattr(core, "run_implement", _instant_run)

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    httpd.registry_path = str(reg)
    httpd.manager = core.RunManager(core.load_registry(str(reg)).projects)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"
    yield base, httpd, project
    httpd.shutdown()
    httpd.server_close()


def _instant_run(project, slug, instruction, *, on_spawn=None, run_id=None):
    from types import SimpleNamespace

    if on_spawn:
        on_spawn(SimpleNamespace(returncode=0))
    yield "▸ Edit alpha.py"
    yield "[docket] run completed"


def _get(base, path):
    with urllib.request.urlopen(base + path) as r:
        return r.status, json.loads(r.read())


def _get_raw(base, path):
    with urllib.request.urlopen(base + path) as r:
        return r.status, r.read(), r.headers.get("Content-Type")


def _post(base, path, body):
    req = urllib.request.Request(
        base + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return r.status, json.loads(r.read())


def _expect_error(fn):
    try:
        fn()
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())
    raise AssertionError("expected an HTTPError")


# --- static -------------------------------------------------------------------


def test_index_html(live_server):
    base, *_ = live_server
    status, data, ctype = _get_raw(base, "/")
    assert status == 200
    assert ctype == "text/html"
    assert b"docket" in data


def test_static_asset(live_server):
    base, *_ = live_server
    status, _, ctype = _get_raw(base, "/static/app.js")
    assert status == 200
    assert ctype == "text/javascript"


def test_static_missing_is_404(live_server):
    base, *_ = live_server
    code, data = _expect_error(lambda: urllib.request.urlopen(base + "/static/nope.js"))
    assert code == 404


def test_static_traversal_blocked(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/static/..%2f..%2fpyproject.toml")
    )
    assert code == 404


# --- read endpoints -----------------------------------------------------------


def test_api_projects(live_server):
    base, *_ = live_server
    status, data = _get(base, "/api/projects")
    assert status == 200
    assert data["projects"][0]["name"] == "repo"
    assert data["projects"][0]["plans"][0]["slug"] == "alpha"


def test_api_plan(live_server):
    base, *_ = live_server
    status, data = _get(base, "/api/plan?project=repo&slug=alpha")
    assert data["title"] == "Alpha"
    assert "# body" in data["body"]


def test_api_plan_unknown_project(live_server):
    base, *_ = live_server
    code, data = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/plan?project=ghost&slug=alpha")
    )
    assert code == 404


def test_api_plan_bad_slug(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/plan?project=repo&slug=../x")
    )
    assert code == 400


def test_api_plan_missing_file(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/plan?project=repo&slug=ghost")
    )
    assert code == 404


def test_api_instruction_template(live_server):
    base, *_ = live_server
    status, data = _get(base, "/api/instruction-template")
    assert "{path}" in data["template"]


def test_api_instruction_template_effective_for_plan(live_server):
    base, *_ = live_server
    status, data = _get(base, "/api/instruction-template?project=repo&slug=alpha")
    assert "alpha.md" in data["template"]
    assert "{path}" not in data["template"]  # resolved per-plan


def test_api_instruction_template_unknown_project(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(
            base + "/api/instruction-template?project=ghost&slug=alpha"
        )
    )
    assert code == 404


def test_api_instruction_template_bad_slug(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(
            base + "/api/instruction-template?project=repo&slug=../x"
        )
    )
    assert code == 400


def test_api_instruction_template_missing_plan(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(
            base + "/api/instruction-template?project=repo&slug=ghost"
        )
    )
    assert code == 404


def test_api_runcmd(live_server):
    base, *_ = live_server
    status, data = _get(base, "/api/runcmd?project=repo&slug=alpha")
    assert "claude -p" in data["cmd"]


def test_api_runcmd_unknown_project(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/runcmd?project=ghost&slug=alpha")
    )
    assert code == 404


def test_api_runcmd_bad_slug(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/runcmd?project=repo&slug=..")
    )
    assert code == 400


def test_unknown_get_route(live_server):
    base, *_ = live_server
    code, _ = _expect_error(lambda: urllib.request.urlopen(base + "/api/nope"))
    assert code == 404


def test_registry_error_is_500(live_server, tmp_path):
    base, httpd, _ = live_server
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps(["not a dict"]), encoding="utf-8")
    httpd.registry_path = str(bad)
    code, data = _expect_error(lambda: urllib.request.urlopen(base + "/api/projects"))
    assert code == 500
    assert "error" in data


# --- manual transitions -------------------------------------------------------


def test_mark_implemented_and_reopen(live_server):
    base, *_ = live_server
    status, data = _post(base, "/api/implemented", {"project": "repo", "slug": "alpha"})
    assert data == {"ok": True, "status": "implemented"}
    status, data = _post(base, "/api/reopen", {"project": "repo", "slug": "alpha"})
    assert data["status"] == "ready"


def test_mark_implemented_conflict(live_server):
    base, *_ = live_server
    _post(base, "/api/implemented", {"project": "repo", "slug": "alpha"})
    code, data = _expect_error(
        lambda: _post(base, "/api/implemented", {"project": "repo", "slug": "alpha"})
    )
    assert code == 409


def test_manual_unknown_project(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: _post(base, "/api/implemented", {"project": "ghost", "slug": "alpha"})
    )
    assert code == 404


def test_manual_bad_slug(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: _post(base, "/api/implemented", {"project": "repo", "slug": ".."})
    )
    assert code == 400


def test_malformed_json_body(live_server):
    base, *_ = live_server
    req = urllib.request.Request(
        base + "/api/implemented",
        data=b"{bad",
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    code, data = _expect_error(lambda: urllib.request.urlopen(req))
    assert code == 400


def test_unknown_post_route(live_server):
    base, *_ = live_server
    code, _ = _expect_error(lambda: _post(base, "/api/nope", {}))
    assert code == 404


def test_post_registry_error_is_500(live_server, tmp_path):
    # a broken registry makes _find_project raise inside a POST handler -> generic 500
    base, httpd, _ = live_server
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps("not a dict"), encoding="utf-8")
    httpd.registry_path = str(bad)
    code, data = _expect_error(
        lambda: _post(base, "/api/implemented", {"project": "repo", "slug": "alpha"})
    )
    assert code == 500


# --- implement + stream + stop ------------------------------------------------


def test_implement_empty_items(live_server):
    base, *_ = live_server
    code, _ = _expect_error(lambda: _post(base, "/api/implement", {"items": []}))
    assert code == 400


def test_implement_invalid_item(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: _post(
            base, "/api/implement", {"items": [{"project": "ghost", "slug": "alpha"}]}
        )
    )
    assert code == 409


def test_implement_and_stream(live_server):
    base, *_ = live_server
    status, data = _post(
        base, "/api/implement", {"items": [{"project": "repo", "slug": "alpha"}]}
    )
    run_id = data["runs"][0]["run_id"]
    body = _read_stream(base, run_id)
    assert "▸ Edit alpha.py" in body
    assert "event: end" in body


def test_stream_unknown_run_404(live_server):
    base, *_ = live_server
    code, _ = _expect_error(
        lambda: urllib.request.urlopen(base + "/api/stream?run_id=ghost")
    )
    assert code == 404


def test_stop_unknown_run_404(live_server):
    base, *_ = live_server
    code, _ = _expect_error(lambda: _post(base, "/api/stop", {"run_id": "ghost"}))
    assert code == 404


def _read_stream(base, run_id, limit=4000):
    with urllib.request.urlopen(base + f"/api/stream?run_id={run_id}") as r:
        chunks = []
        while len(b"".join(chunks)) < limit:
            line = r.readline()
            if not line:
                break
            chunks.append(line)
            if line.startswith(b"event: end"):
                r.readline()  # the data: <state> line
                break
        return b"".join(chunks).decode()
