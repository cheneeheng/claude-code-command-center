"""Local HTTP server: the JSON API plus the built frontend.

Bound to 127.0.0.1 by default. Every request must carry a ``Host`` of
``127.0.0.1:<port>`` or ``localhost:<port>``: the payload includes session titles
taken from prompts, so this guards against DNS rebinding.
"""

from __future__ import annotations

import json
import mimetypes
import os
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlsplit

from ag_ui.core import RunAgentInput
from ag_ui.encoder import EventEncoder

from usage_insights import agent, aggregate, export, query, reference, store
from usage_insights.inventory import Inventory, load_inventory

STATIC_DIR = Path(__file__).parent / "static"
QUERY_MAX_BYTES = 16384
LAYOUT_MAX_BYTES = 262144
AGENT_MAX_BYTES = 1048576  # a run carries the whole AG-UI message list


class Server(ThreadingHTTPServer):
    """The dashboard server and what its handlers need."""

    # On Windows SO_REUSEADDR lets a second bind onto a busy port succeed.
    allow_reuse_address = False
    daemon_threads = True

    def __init__(
        self, host: str, port: int, db: Path, claude_dirs: list[Path], static_dir: Path
    ) -> None:
        super().__init__((host, port), Handler)
        self.db = db
        self.claude_dirs = claude_dirs
        self.static_dir = static_dir
        self.allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}


def make_server(
    host: str, port: int, db: Path, claude_dirs: list[Path], static_dir: Path = STATIC_DIR
) -> Server:
    """Bind the server. Raises ``OSError`` when the port is taken."""
    return Server(host, port, db, claude_dirs, static_dir)


def _project_paths(db: Path) -> list[Path]:
    """Session working dirs that still exist: their project config counts as installed."""
    if not db.is_file():
        return []
    with store.connect_read_only(db) as conn:
        rows = conn.execute("SELECT DISTINCT cwd FROM sessions WHERE cwd IS NOT NULL")
        return [p for (cwd,) in rows if (p := Path(cwd)).is_dir()]


class Handler(BaseHTTPRequestHandler):
    server: Server

    def log_message(self, format: str, *args: Any) -> None:
        """Stay quiet: the background task has no console."""

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, data: object) -> None:
        self._send(status, json.dumps(data).encode(), "application/json")

    def _host_ok(self) -> bool:
        if self.headers.get("Host", "") in self.server.allowed_hosts:
            return True
        self._json(HTTPStatus.FORBIDDEN, {"error": "forbidden host"})
        return False

    def _same_origin(self) -> bool:
        """Whether a POST came from this page, not from another site's form or fetch.

        ``Sec-Fetch-Site`` decides when the browser sends it: the Vite dev proxy keeps
        the dev server's ``Origin`` but the browser still calls it same-origin.
        """
        site = self.headers.get("Sec-Fetch-Site")
        if site is not None:
            return site in ("same-origin", "none")
        origin = self.headers.get("Origin")
        return origin is None or urlsplit(origin).netloc in self.server.allowed_hosts

    def do_GET(self) -> None:
        if not self._host_ok():
            return
        url = urlsplit(self.path)
        if url.path == "/api/health":
            self._json(HTTPStatus.OK, {"ok": True})
        elif url.path == "/api/summary":
            self._summary(parse_qs(url.query).get("range", ["30d"])[0])
        elif url.path == "/api/layout":
            self._get_layout()
        elif url.path == "/" or url.path.startswith("/assets/"):
            self._static(url.path)
        else:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:
        if not self._host_ok():
            return
        url = urlsplit(self.path)
        routes = {
            "/api/refresh": self._refresh,
            "/api/query": self._query,
            # Same-origin like every POST: each run spends the user's API credit.
            "/api/agent": self._agent,
        }
        handler = routes.get(url.path)
        if handler is None:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        if not self._same_origin():
            self._json(HTTPStatus.FORBIDDEN, {"error": "cross-site request"})
            return
        handler(parse_qs(url.query))

    def _layout_write_allowed(self) -> bool:
        """Host and same-origin checks for PUT and DELETE; ``False`` once answered."""
        if not self._host_ok():
            return False
        if urlsplit(self.path).path != "/api/layout":
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return False
        if not self._same_origin():
            self._json(HTTPStatus.FORBIDDEN, {"error": "cross-site request"})
            return False
        return True

    def _no_content(self) -> None:
        self._send(HTTPStatus.NO_CONTENT, b"", "text/plain")

    def _layout_path(self) -> Path:
        return self.server.db.parent / "layout.json"

    def _get_layout(self) -> None:
        try:
            layout = json.loads(self._layout_path().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            layout = None  # none saved, or unreadable: the page uses the default
        if isinstance(layout, dict):
            self._json(HTTPStatus.OK, layout)
        else:
            self._no_content()

    def do_PUT(self) -> None:
        if not self._layout_write_allowed():
            return
        try:
            layout = self._read_json(LAYOUT_MAX_BYTES)
            if not (
                isinstance(layout, dict)
                and layout.get("version") == 1
                and isinstance(layout.get("sections"), list)
            ):
                raise ValueError("layout must be an object with version 1 and a sections list")
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        path = self._layout_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name("layout.json.tmp")
        tmp.write_text(json.dumps(layout), encoding="utf-8")
        os.replace(tmp, path)  # a crash never leaves half a file
        self._no_content()

    def do_DELETE(self) -> None:
        if not self._layout_write_allowed():
            return
        self._layout_path().unlink(missing_ok=True)
        self._no_content()

    def _read_json(self, max_bytes: int) -> Any:
        """The request body as JSON. Raises ``ValueError`` when too large or not JSON."""
        length = int(self.headers.get("Content-Length") or 0)
        if length > max_bytes:
            raise ValueError(f"request body is over {max_bytes} bytes")
        return json.loads(self.rfile.read(length) or b"null")

    def _inventory(self, ref: reference.Reference) -> Inventory:
        db = self.server.db
        return load_inventory(self.server.claude_dirs, _project_paths(db), ref.tools, ref.agents)

    def _query(self, qs: dict[str, list[str]]) -> None:
        try:
            spec = query.parse(self._read_json(QUERY_MAX_BYTES), qs.get("range", ["30d"])[0])
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        try:
            ref = reference.load(self.server.db.parent)
            skills = (
                frozenset(i.name for i in self._inventory(ref).skills)
                if spec.metric == "skill_uses" else frozenset()
            )
            data = query.run(
                self.server.db, spec, datetime.now().astimezone(), None, ref.prices, skills
            )
        except Exception as exc:  # noqa: BLE001 - reported to the page, not swallowed
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})
            return
        self._json(HTTPStatus.OK, data)

    def _agent(self, _qs: dict[str, list[str]]) -> None:
        key = agent.api_key()
        if key is None:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE,
                       {"error": f"set {agent.KEY_VAR} to use the chat"})
            return
        try:
            run_input = RunAgentInput.model_validate(self._read_json(AGENT_MAX_BYTES))
        except ValueError as exc:  # pydantic's ValidationError is a ValueError
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        db = self.server.db

        def skill_names() -> frozenset[str]:
            return frozenset(i.name for i in self._inventory(reference.load(db.parent)).skills)

        ctx = agent.Context(db, skill_names)
        encoder = EventEncoder(accept=self.headers.get("Accept", "text/event-stream"))
        try:
            with agent.checkout(run_input.thread_id) as thread:
                # HTTP/1.0 and no Content-Length: the stream ends when the connection closes.
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", encoder.get_content_type())
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                events = agent.run(
                    thread, run_input, ctx, agent.make_client(key), agent.model_name()
                )

                def write(chunk: bytes) -> None:
                    self.wfile.write(chunk)
                    self.wfile.flush()

                agent.pump(events, encoder.encode, write)
        except agent.Busy:
            self._json(HTTPStatus.CONFLICT, {"error": "this chat is already running"})

    def _refresh(self, _qs: dict[str, list[str]]) -> None:
        try:
            result = export.run_export(self.server.db, self.server.claude_dirs, progress=_quiet)
        except store.ExportBusy:
            self._json(HTTPStatus.CONFLICT, {"error": "export already running"})
            return
        except Exception as exc:  # noqa: BLE001 - reported to the page, not swallowed
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})
            return
        self._json(HTTPStatus.OK, result.__dict__)

    def _summary(self, range_key: str) -> None:
        db = self.server.db
        now = datetime.now().astimezone()
        try:
            ref = reference.load(db.parent)
            inventory = self._inventory(ref)
            # tz None: local dates follow the system zone's rules at each timestamp, so
            # history from before a DST change keeps that day's offset.
            data = aggregate.summary(
                db, inventory, range_key, now, self.server.claude_dirs, None,
                prices=ref.prices, prices_as_of=ref.prices_fetched,
            )
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        except Exception as exc:  # noqa: BLE001 - e.g. a store without schema; the page shows it
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})
            return
        data["chat"] = {"enabled": agent.api_key() is not None}
        self._json(HTTPStatus.OK, data)

    def _static(self, path: str) -> None:
        root = self.server.static_dir.resolve()
        index = root / "index.html"
        if path == "/":
            if not index.is_file():
                self._send(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    b"frontend not built: run the setup script",
                    "text/plain; charset=utf-8",
                )
                return
            target = index
        else:
            target = (root / path.lstrip("/")).resolve()
            if root / "assets" not in target.parents or not target.is_file():
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self._send(HTTPStatus.OK, target.read_bytes(), content_type)


def _quiet(_line: str) -> None:
    """Export progress has nowhere to go from a request handler."""
