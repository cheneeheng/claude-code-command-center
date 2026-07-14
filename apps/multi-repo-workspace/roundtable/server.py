"""Localhost browser server: stdlib ThreadingHTTPServer + JSON API + SSE.

No web framework, no build step. Binds 127.0.0.1 only — that is the entire auth
story (docket precedent). Same-origin only; no CORS headers, no cookies. Route
handlers contain no business logic: they validate (path params through safe_slug,
bodies against expected keys, unknown keys rejected) and call core modules; status
mutations go only through tracker/rounds.
"""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import parse_qs, unquote, urlparse

from roundtable import gitinfo, gitwrite, locks, plans, registry, tracker
from roundtable.executor import Executor
from roundtable.locks import Conflict
from roundtable.plans import safe_slug
from roundtable.registry import Config, Project
from roundtable.rounds import RoundStore
from roundtable.sessions import SessionManager

STATIC_DIR = Path(__file__).parent / "static"
_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json",
    ".svg": "image/svg+xml",
}


def _check_body(
    body: dict[str, Any],
    required: set[str],
    optional: set[str] | frozenset[str] = frozenset(),
) -> None:
    """Reject missing required keys and unknown keys (closed request shapes)."""
    missing = required - body.keys()
    if missing:
        raise ValueError(f"missing key(s): {', '.join(sorted(missing))}")
    unknown = body.keys() - required - optional
    if unknown:
        raise ValueError(f"unknown key(s): {', '.join(sorted(unknown))}")


class Handler(BaseHTTPRequestHandler):
    server_version = "roundtable/0.1"

    # --- plumbing -----------------------------------------------------------------

    @property
    def app(self) -> "AppState":
        app: AppState = self.server.app  # type: ignore[attr-defined]  # set by make_server
        return app

    def _config(self) -> Config:
        """Reload the registry each request — files are the source of truth."""
        return registry.load_registry(self.app.registry_path)

    def _projects(self) -> dict[str, Project]:
        return {p.name: p for p in self._config().projects}

    def _project(self, name: str) -> Project:
        project = self._projects().get(name)
        if project is None:
            raise KeyError(f"unknown project: {name}")
        return project

    def _send_json(self, obj: Any, status: int = 200) -> None:
        payload = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _error(self, code: str, detail: str, status: int, **extra: Any) -> None:
        self._send_json({"error": code, "detail": detail, **extra}, status)

    def _read_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw or b"{}")
        if not isinstance(body, dict):
            raise ValueError("body must be a JSON object")
        return body

    def log_message(self, fmt: str, *args: Any) -> None:  # quieter default logging
        pass

    def _send_sse(self, gen: Iterator[tuple[str, Any]]) -> None:
        """Emit an SSE stream: every data payload is one single-line JSON object."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        # The stream is finite (it ends with the `end` event); close the socket so
        # clients see EOF instead of a hung keep-alive connection.
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        try:
            for kind, value in gen:
                if kind == "keepalive":
                    chunk = ": ping\n\n"
                elif kind == "end":
                    chunk = f"event: end\ndata: {json.dumps({'status': value})}\n\n"
                else:
                    data = (
                        value
                        if isinstance(value, dict)
                        else {
                            "kind": "line",
                            "text": value,
                        }
                    )
                    chunk = f"data: {json.dumps(data)}\n\n"
                self.wfile.write(chunk.encode("utf-8"))
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):  # pragma: no cover
            pass  # client disconnected mid-stream — timing-dependent, untestable

    # --- HTTP methods ----------------------------------------------------------------

    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_PUT(self) -> None:
        self._dispatch("PUT")

    def do_DELETE(self) -> None:
        self._dispatch("DELETE")

    def _dispatch(self, method: str) -> None:
        url = urlparse(self.path)
        path = unquote(url.path)
        qs = parse_qs(url.query)
        try:
            body: dict[str, Any] = {}
            if method in ("POST", "PUT"):
                try:
                    body = self._read_body()
                except (json.JSONDecodeError, ValueError) as exc:
                    return self._error("bad_request", f"malformed body: {exc}", 400)
            self._route(method, path, qs, body)
        except gitinfo.StaleFile as exc:
            self._error("stale_file", "file changed on disk", 409, mtime=exc.mtime)
        except gitinfo.BinaryFile:
            self._error("binary_file", "not a text file", 415)
        except gitinfo.FileTooLarge as exc:
            self._error("too_large", str(exc), 413)
        except Conflict as exc:
            self._error(exc.code, exc.detail, 409)
        except (KeyError, FileNotFoundError) as exc:
            self._error("not_found", str(exc), 404)
        except ValueError as exc:
            self._error("bad_request", str(exc), 400)
        except gitinfo.GitError as exc:
            self._error("git_error", str(exc), 500)
        except (BrokenPipeError, ConnectionResetError):  # pragma: no cover
            pass  # client disconnected mid-response — timing-dependent, untestable
        except Exception as exc:  # noqa: BLE001 — surface as 500 with the message
            self._error("internal", str(exc), 500)

    # --- routing --------------------------------------------------------------------

    def _route(
        self,
        method: str,
        path: str,
        qs: dict[str, list[str]],
        body: dict[str, Any],
    ) -> None:
        if method == "GET":
            if path == "/":
                return self._serve_static("index.html")
            if path.startswith("/static/"):
                return self._serve_static(path[len("/static/") :])
            if path == "/api/config":
                return self._api_config()
            if path == "/api/board":
                return self._api_board()
            if path == "/api/rounds":
                return self._send_json({"rounds": self.app.rounds.list_rounds()})
            if path == "/api/rounds/current":
                return self._send_json(self.app.rounds.current())
            if path == "/api/sessions":
                project = qs.get("project", [None])[0]
                return self._send_json(
                    {"sessions": self.app.sessions.list_sessions(project)}
                )

        parts = [p for p in path.split("/") if p]
        if len(parts) < 2 or parts[0] != "api":
            raise KeyError(path)

        if parts[1] == "repos" and len(parts) >= 4:
            return self._route_repo(method, parts, qs, body)
        if parts[1] == "sessions" and (len(parts) >= 3 or method == "POST"):
            return self._route_session(method, parts, body)
        if parts[1] == "rounds" and len(parts) >= 3:
            return self._route_round(method, parts, body)
        if parts[1] == "orders" and len(parts) == 4:
            return self._route_order(method, parts, body)
        raise KeyError(path)

    # --- static -----------------------------------------------------------------------

    def _serve_static(self, rel: str) -> None:
        target = (STATIC_DIR / rel).resolve()
        if STATIC_DIR.resolve() not in target.parents or not target.is_file():
            return self._error("not_found", rel, 404)
        data = target.read_bytes()
        self.send_response(200)
        self.send_header(
            "Content-Type",
            _CONTENT_TYPES.get(target.suffix, "application/octet-stream"),
        )
        self.send_header("Content-Length", str(len(data)))
        # No build step / no cache-busting filenames: without this, a browser tab left
        # open across a server restart can keep serving stale JS/CSS from cache.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    # --- config / board -----------------------------------------------------------------

    def _api_config(self) -> None:
        cfg = self._config()
        self._send_json(
            {
                "port": cfg.port,
                "registry_search_paths": registry.registry_search_paths(
                    self.app.registry_path
                ),
                "projects": [vars(p) for p in cfg.projects],
            }
        )

    def _api_board(self) -> None:
        projects = self._config().projects
        current = self.app.rounds.current()
        by_repo: dict[str, dict[str, int]] = {}
        for order in current["orders"]:
            slot = by_repo.setdefault(order["project"], {"orders": 0, "running": 0})
            slot["orders"] += 1
            if order["state"] == "running":
                slot["running"] += 1
        done = next(
            (r for r in self.app.rounds.list_rounds() if r["status"] == "done"), None
        )
        cards: list[dict[str, Any]] = []
        for project in projects:
            state, git_error = gitinfo.repo_state(project.path)
            cards.append(
                {
                    "name": project.name,
                    "path": project.path,
                    "state": state,
                    "git_error": git_error,
                    "plans": plans.plan_counts(project),
                    "sessions": {
                        "streaming": self.app.sessions.streaming_count(project.name)
                    },
                    "round": by_repo.get(project.name),
                }
            )
        states = [o["state"] for o in current["orders"]]
        self._send_json(
            {
                "projects": cards,
                "round": {
                    "id": current["id"],
                    "number": current["number"],
                    "status": current["status"],
                    "orders": len(states),
                    "terminal": sum(
                        1
                        for s in states
                        if s in ("succeeded", "failed", "stopped", "skipped")
                    ),
                    "carried_followups": len(current["carried_followups"]),
                    "cost_est_usd": current["cost_est_usd"],
                },
                "last_done": None
                if done is None
                else {
                    "number": done["number"],
                    "succeeded": sum(
                        1 for o in done["orders"] if o["state"] == "succeeded"
                    ),
                    "failed": sum(
                        1 for o in done["orders"] if o["state"] in ("failed", "stopped")
                    ),
                    "cost_est_usd": done["cost_est_usd"],
                },
            }
        )

    # --- repos -------------------------------------------------------------------------

    def _route_repo(
        self,
        method: str,
        parts: list[str],
        qs: dict[str, list[str]],
        body: dict[str, Any],
    ) -> None:
        project = self._project(parts[2])
        rest = parts[3:]

        if method == "GET" and rest == ["tree"]:
            rel = qs.get("path", [""])[0]
            return self._send_json(
                {"path": rel, "entries": gitinfo.tree(project.path, rel)}
            )
        if rest == ["file"]:
            rel = qs.get("path", [""])[0]
            if not rel:
                raise ValueError("path query parameter is required")
            if method == "GET":
                return self._send_json(gitinfo.read_file(project.path, rel))
            if method == "PUT":
                _check_body(body, {"content", "expect_mtime"})
                if not isinstance(body["content"], str):
                    raise ValueError("content must be a string")
                expect = body["expect_mtime"]
                if expect is not None and not isinstance(expect, int):
                    raise ValueError("expect_mtime must be an integer or null")
                if locks.is_held(project.path):
                    raise Conflict(
                        "repo_busy",
                        f"repo is busy ({locks.holder(project.path)})",
                    )
                mtime = gitinfo.save_file(project.path, rel, body["content"], expect)
                return self._send_json({"mtime": mtime})
        if method == "GET" and rest == ["log"]:
            n = int(qs.get("n", ["30"])[0])
            return self._send_json({"commits": gitinfo.log(project.path, n)})
        if method == "GET" and rest == ["diff"]:
            return self._send_json(gitinfo.diff(project.path))
        if method == "GET" and rest == ["plans"]:
            return self._send_json(
                {
                    "plans": [
                        {
                            "slug": p.slug,
                            "title": p.title,
                            "status": p.status,
                            "mtime": p.mtime,
                        }
                        for p in plans.list_plans(project)
                    ]
                }
            )
        if method == "GET" and len(rest) >= 2 and rest[0] == "plans":
            slug = safe_slug("/".join(rest[1:]))
            plan = plans.read_plan(project, slug)
            return self._send_json(
                {
                    "project": plan.project,
                    "slug": plan.slug,
                    "title": plan.title,
                    "status": plan.status,
                    "body": plan.body,
                    "meta": plan.meta,
                    "history": plan.history,
                    "manual_command": plans.manual_command(project, slug),
                }
            )
        if (
            method == "POST"
            and len(rest) >= 3
            and rest[0] == "plans"
            and rest[-1] == "status"
        ):
            slug = safe_slug("/".join(rest[1:-1]))
            _check_body(body, {"to"})
            to = body["to"]
            if to not in ("ready", "implemented"):  # closed set; free-form rejected
                raise ValueError(f"invalid target status: {to!r}")
            plans.read_plan(project, slug)  # 404 for a plan that does not exist
            try:
                rec = tracker.set_status(project, slug, to, trigger="manual")
            except ValueError as exc:
                raise Conflict("illegal_transition", str(exc)) from exc
            return self._send_json({"ok": True, "status": rec["status"]})
        if method == "POST" and rest == ["commit"]:
            _check_body(body, {"message"})
            if locks.is_held(project.path):
                raise Conflict(
                    "repo_busy", f"repo is busy ({locks.holder(project.path)})"
                )
            return self._send_json(gitwrite.commit(project.path, str(body["message"])))
        raise KeyError("/".join(parts))

    # --- sessions ------------------------------------------------------------------------

    def _route_session(
        self, method: str, parts: list[str], body: dict[str, Any]
    ) -> None:
        mgr = self.app.sessions
        if method == "POST" and parts == ["api", "sessions"]:
            _check_body(body, {"project", "prompt"})
            project = self._project(str(body["project"]))
            prompt = str(body["prompt"]).strip()
            if not prompt:
                raise ValueError("prompt must not be empty")
            return self._send_json(mgr.create(project, prompt), 201)
        sid = parts[2]  # non-create sessions routes always carry an id (route gate)
        if method == "GET" and len(parts) == 3:
            return self._send_json(mgr.get(sid))
        if method == "GET" and parts[3:] == ["stream"]:
            return self._send_sse(mgr.attach(sid))
        if method == "POST" and parts[3:] == ["message"]:
            _check_body(body, {"prompt"})
            prompt = str(body["prompt"]).strip()
            if not prompt:
                raise ValueError("prompt must not be empty")
            meta = mgr.meta(sid)  # resolve the session's project for the turn
            project = self._project(str(meta["project"]))
            return self._send_json(mgr.message(project, sid, prompt))
        if method == "POST" and parts[3:] == ["stop"]:
            return self._send_json(mgr.stop(sid))
        if method == "POST" and parts[3:] == ["close"]:
            return self._send_json(mgr.close(sid))
        raise KeyError("/".join(parts))

    # --- rounds --------------------------------------------------------------------------

    def _route_round(self, method: str, parts: list[str], body: dict[str, Any]) -> None:
        store = self.app.rounds
        rest = parts[2:]
        if method == "GET" and len(rest) == 1 and rest[0] != "current":
            return self._send_json(store.get(rest[0]))
        if method == "POST" and rest == ["current", "orders"]:
            _check_body(body, {"project", "slug"}, {"instruction"})
            project = self._project(str(body["project"]))
            order = store.add_order(project, str(body["slug"]), body.get("instruction"))
            return self._send_json(order, 201)
        if method == "DELETE" and len(rest) == 3 and rest[:2] == ["current", "orders"]:
            store.remove_order(rest[2])
            return self._send_json({"ok": True})
        if method == "POST" and rest == ["current", "end-turn"]:
            _check_body(body, set())
            projects = self._projects()
            rnd = store.end_turn(projects)
            self.app.executor.start(projects, rnd)
            return self._send_json(store.get(rnd["id"]))
        if method == "POST" and rest == ["current", "stop"]:
            _check_body(body, set())
            self.app.executor.stop()
            return self._send_json(store.stop())
        if method == "POST" and rest == ["current", "close"]:
            _check_body(body, set())
            return self._send_json(store.close())
        if method == "POST" and rest == ["current", "followups", "dismiss"]:
            _check_body(body, {"index"})
            store.dismiss_followup(int(body["index"]))
            return self._send_json({"ok": True})
        raise KeyError("/".join(parts))

    # --- orders --------------------------------------------------------------------------

    def _route_order(self, method: str, parts: list[str], body: dict[str, Any]) -> None:
        store = self.app.rounds
        oid, action = parts[2], parts[3]
        rnd, order = store.find_order(oid)
        if method == "GET" and action == "stream":
            return self._send_sse(
                self.app.executor.attach(rnd["id"], oid, str(order["state"]))
            )
        if method == "GET" and action == "output":
            return self._send_json(
                {"lines": store.read_output(rnd["id"], oid), "state": order["state"]}
            )
        if method == "POST" and action == "reviewed":
            _check_body(body, {"reviewed"})
            if not isinstance(body["reviewed"], bool):
                raise ValueError("reviewed must be a boolean")
            return self._send_json(store.set_reviewed(oid, body["reviewed"]))
        if method == "POST" and action == "followup":
            _check_body(body, {"note"})
            return self._send_json(store.set_followup(oid, str(body["note"])))
        if method == "POST" and action == "instruction":
            _check_body(body, {"instruction"})
            instruction = body["instruction"]
            if instruction is not None and not isinstance(instruction, str):
                raise ValueError("instruction must be a string or null")
            return self._send_json(store.set_instruction(oid, instruction))
        raise KeyError("/".join(parts))


class AppState:
    """Shared managers hung off the HTTP server instance."""

    def __init__(
        self, registry_path: str | None, state_dir: Path | None = None
    ) -> None:
        self.registry_path = registry_path
        self.sessions = SessionManager(state_dir)
        self.rounds = RoundStore(state_dir)
        self.executor = Executor(self.rounds)


def make_server(
    port: int, registry_path: str | None, state_dir: Path | None = None
) -> ThreadingHTTPServer:
    """Build the bound server + app state and run startup recovery."""
    config = registry.load_registry(registry_path)
    app = AppState(registry_path, state_dir)
    reset = tracker.reset_stale_runs(config.projects)
    if reset:
        print(f"[roundtable] reset {len(reset)} stale running sidecar(s) to ready")
    recovered = app.sessions.recover()
    if recovered:
        print(f"[roundtable] marked {recovered} interrupted session(s) idle")
    if app.rounds.recover():
        print("[roundtable] moved an interrupted executing round to review")
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.app = app  # type: ignore[attr-defined]
    return httpd


def run_server(port: int | None = None, registry_path: str | None = None) -> int:
    """`roundtable serve`: bind 127.0.0.1 and serve until Ctrl-C."""
    config = registry.load_registry(registry_path)
    # Port resolution: code default -> Config.port -> --port flag (flag wins).
    resolved_port = config.port if port is None else port
    httpd = make_server(resolved_port, registry_path)
    print(f"[roundtable] serving on http://127.0.0.1:{resolved_port}  (Ctrl-C to stop)")
    if not config.projects:
        print("[roundtable] no projects — searched:")
        for p in registry.registry_search_paths(registry_path):
            print(f"            {p}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[roundtable] shutting down")
    finally:
        httpd.server_close()
    return 0
