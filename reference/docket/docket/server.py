"""Localhost browser server: stdlib ThreadingHTTPServer + JSON API + SSE.

No web framework, no build step. Binds to 127.0.0.1 only — that is the auth story for a
single-user local tool: not reachable off-box.
"""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from docket import core, tracker

STATIC_DIR = Path(__file__).parent / "static"
_CONTENT_TYPES = {".html": "text/html", ".js": "text/javascript", ".css": "text/css"}


class Handler(BaseHTTPRequestHandler):
    server_version = "docket/0.1"

    # --- helpers --------------------------------------------------------------

    @property
    def registry_path(self):
        return self.server.registry_path

    @property
    def manager(self) -> core.RunManager:
        return self.server.manager

    def _projects(self) -> list[core.Project]:
        """Reload the registry each request — plan files are the source of truth."""
        projects = core.load_registry(self.registry_path).projects
        self.manager.set_projects(projects)
        return projects

    def _find_project(self, name: str) -> core.Project | None:
        return next((p for p in self._projects() if p.name == name), None)

    def _send_json(self, obj, status: int = 200) -> None:
        payload = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        return json.loads(raw or b"{}")

    def log_message(self, fmt, *args):  # quieter default logging
        pass

    # --- routing --------------------------------------------------------------

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path
        qs = parse_qs(url.query)
        try:
            if path == "/":
                return self._serve_static("index.html")
            if path.startswith("/static/"):
                return self._serve_static(path[len("/static/") :])
            if path == "/api/projects":
                return self._api_projects()
            if path == "/api/plan":
                return self._api_plan(qs)
            if path == "/api/instruction-template":
                return self._api_instruction_template(qs)
            if path == "/api/runcmd":
                return self._api_runcmd(qs)
            if path == "/api/stream":
                return self._api_stream(qs)
            self._send_json({"error": "not found"}, 404)
        except BrokenPipeError:
            pass
        except Exception as exc:  # noqa: BLE001 — surface as 500 with the message
            self._send_json({"error": str(exc)}, 500)

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            body = self._read_body()
        except (json.JSONDecodeError, ValueError):
            return self._send_json({"error": "malformed JSON body"}, 400)
        try:
            if path == "/api/implemented":
                return self._api_manual(body, "implemented")
            if path == "/api/reopen":
                return self._api_manual(body, "ready")
            if path == "/api/implement":
                return self._api_implement(body)
            if path == "/api/stop":
                return self._api_stop(body)
            self._send_json({"error": "not found"}, 404)
        except Exception as exc:  # noqa: BLE001
            self._send_json({"error": str(exc)}, 500)

    # --- static ---------------------------------------------------------------

    def _serve_static(self, rel: str):
        target = (STATIC_DIR / rel).resolve()
        if STATIC_DIR.resolve() not in target.parents or not target.is_file():
            return self._send_json({"error": "not found"}, 404)
        data = target.read_bytes()
        self.send_response(200)
        self.send_header(
            "Content-Type",
            _CONTENT_TYPES.get(target.suffix, "application/octet-stream"),
        )
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # --- API ------------------------------------------------------------------

    def _api_instruction_template(self, qs):
        """Effective template for a plan (project override → defaults → constant, {path}
        filled); param-less returns the global default with {path} left literal."""
        name = qs.get("project", [""])[0]
        slug = qs.get("slug", [""])[0]
        if not name or not slug:
            return self._send_json(
                {"template": core.default_instruction_template(self.registry_path)}
            )
        project = self._find_project(name)
        if project is None:
            return self._send_json({"error": "unknown project"}, 404)
        try:
            core.read_plan(project, slug)  # 400 on bad slug, 404 on missing plan
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 400)
        except FileNotFoundError as exc:
            return self._send_json({"error": str(exc)}, 404)
        self._send_json({"template": core.resolve_instruction(project, slug, None)})

    def _api_projects(self):
        out = []
        for project in self._projects():
            plans = [
                {"slug": p.slug, "title": p.title, "status": p.status}
                for p in core.list_plans(project)
            ]
            out.append({"name": project.name, "path": project.path, "plans": plans})
        self._send_json({"projects": out})

    def _api_plan(self, qs):
        project = self._find_project(qs.get("project", [""])[0])
        slug = qs.get("slug", [""])[0]
        if project is None:
            return self._send_json({"error": "unknown project"}, 404)
        try:
            core.safe_slug(slug)
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 400)
        try:
            plan = core.read_plan(project, slug)
        except FileNotFoundError as exc:
            return self._send_json({"error": str(exc)}, 404)
        self._send_json(
            {
                "project": plan.project,
                "slug": plan.slug,
                "title": plan.title,
                "status": plan.status,
                "body": plan.body,
                "history": plan.history,
            }
        )

    def _api_runcmd(self, qs):
        project = self._find_project(qs.get("project", [""])[0])
        slug = qs.get("slug", [""])[0]
        if project is None:
            return self._send_json({"error": "unknown project"}, 404)
        try:
            cmd = core.manual_command(project, slug)
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 400)
        self._send_json({"cmd": cmd})

    def _api_manual(self, body, to: str):
        project = self._find_project(body.get("project", ""))
        slug = body.get("slug", "")
        if project is None:
            return self._send_json({"error": "unknown project"}, 404)
        try:
            core.safe_slug(slug)
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 400)
        try:
            rec = tracker.set_status(project, slug, to, trigger="manual")
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 409)
        self._send_json({"ok": True, "status": rec["status"]})

    def _api_implement(self, body):
        items = body.get("items")
        if not isinstance(items, list) or not items:
            return self._send_json({"error": "items must be a non-empty list"}, 400)
        self._projects()  # refresh the manager's project set
        try:
            runs = self.manager.submit(items)
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 409)
        self._send_json(
            {
                "runs": [
                    {
                        "project": r.project,
                        "slug": r.slug,
                        "run_id": r.run_id,
                        "state": r.state,
                    }
                    for r in runs
                ]
            }
        )

    def _api_stop(self, body):
        run_id = body.get("run_id", "")
        try:
            self.manager.stop(run_id)
        except KeyError:
            return self._send_json({"error": "unknown run"}, 404)
        except ValueError as exc:
            return self._send_json({"error": str(exc)}, 409)
        self._send_json({"ok": True})

    def _api_stream(self, qs):
        run_id = qs.get("run_id", [""])[0]
        try:
            gen = self.manager.stream(run_id)
        except KeyError:
            return self._send_json({"error": "unknown run"}, 404)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            for kind, value in gen:
                if kind == "keepalive":
                    chunk = ": keep-alive\n\n"
                elif kind == "end":
                    chunk = f"event: end\ndata: {value}\n\n"
                else:
                    chunk = "".join(f"data: {ln}\n" for ln in value.split("\n")) + "\n"
                self.wfile.write(chunk.encode("utf-8"))
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass  # client disconnected; the live queue is drained once (MVP)


def run_server(port: int | None = None, registry: str | None = None) -> int:
    config = core.load_registry(registry)
    projects = config.projects
    # Port resolution: code default → Config.port → --port flag (flag wins when given).
    if port is None:
        port = config.port
    reset = tracker.reset_stale_runs(projects)
    if reset:
        print(f"[docket] reset {len(reset)} stale run(s) to ready")

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.registry_path = registry
    httpd.manager = core.RunManager(projects)

    print(f"[docket] serving on http://127.0.0.1:{port}  (Ctrl-C to stop)")
    if not projects:
        print("[docket] no projects — searched:")
        for p in core.registry_search_paths(registry):
            print(f"          {p}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[docket] shutting down")
    finally:
        httpd.server_close()
    return 0
