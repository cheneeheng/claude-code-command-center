import json
import os
import queue
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn

import claude_plugins

# ── Constants ──────────────────────────────────────────────────────────────
PLUGINS_BASE      = Path.home() / ".claude" / "plugins"
MARKETPLACES_JSON = PLUGINS_BASE / "known_marketplaces.json"


def _mock_plugins() -> dict:
    return {
        "local": [
            {"id": "ceh-dev-tools@ceh-plugins", "version": "1.1.0", "installPath": ""}
        ],
        "project": [],
        "user": [
            {"id": "frontend-design@anthropic", "version": "2.0.1", "installPath": ""}
        ],
        "mock": True,
    }


def load_installed_plugins(project_root: Path) -> dict:
    """Bucket installed plugins by scope (local/project/user) for project_root.

    Thin wrapper over claude_plugins.load_installed_plugins that preserves this
    app's dev aid: when installed_plugins.json is absent, return mock data
    (includes "mock": True). See docs/shared-plugin-logic.md.
    """
    if not (PLUGINS_BASE / "installed_plugins.json").exists():
        return _mock_plugins()
    return claude_plugins.load_installed_plugins(project_root)


def load_settings_local(project_root: Path) -> dict:
    path = project_root / ".claude" / "settings.local.json"
    if not path.exists():
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(str(path)) from e


def load_settings_project(project_root: Path) -> dict:
    """Reads <project>/.claude/settings.json (PROJECT scope, committed).
    Mirror of load_settings_local; {} if missing/unparseable."""
    path = Path(project_root) / ".claude" / "settings.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return {}


def load_settings_user() -> dict:
    """Reads ~/.claude/settings.json (USER scope, all projects).
    Mirror of load_settings_local; {} if missing/unparseable."""
    path = Path.home() / ".claude" / "settings.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return {}


def save_settings_local(project_root: Path, settings: dict) -> None:
    dir_ = project_root / ".claude"
    dir_.mkdir(parents=True, exist_ok=True)
    path = dir_ / "settings.local.json"
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)


def save_settings_project(project_root: Path, settings: dict) -> None:
    path = Path(project_root) / ".claude" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def save_settings_user(settings: dict) -> None:
    path = Path.home() / ".claude" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def build_sections(raw: dict, settings: dict) -> dict:
    """
    raw      = { "local": [...], "project": [...], "user": [...] } from load_installed_plugins()
               (each entry: {id, version, installPath}; projectPath already matched at load time)
    settings = { "local": {enabledPlugins}, "project": {enabledPlugins}, "user": {enabledPlugins} }
    Returns  { "local": [rows], "project": [rows], "user": [rows] }

    A plugin id belongs to a section if it is installed at that scope OR keyed in that
    scope's enabledPlugins (registry ∪ settings, per scope).
    """
    def section(scope: str) -> list[dict]:
        installed_entries = {e["id"]: e for e in raw[scope]}
        enabled_map = settings[scope]
        ids = set(installed_entries) | set(enabled_map)  # union: registry ∪ this scope's settings
        rows = []
        for pid in sorted(ids):
            name, marketplace = pid.split("@", 1) if "@" in pid else (pid, "")
            entry = installed_entries.get(pid)
            installed = entry is not None
            install_path = entry.get("installPath", "") if entry is not None else ""
            rows.append({
                "id": pid,
                "name": name,
                "marketplace": marketplace,
                "version": entry.get("version", "") if entry is not None else "",
                "scope": scope,
                "enabled": enabled_map.get(pid, True),  # default: enabled
                "installed": installed,
                "skills": [{"name": m.name, "description": m.description}
                           for m in claude_plugins.load_plugin_skills(install_path)] if installed else [],
                "agents": [{"name": m.name, "description": m.description}
                           for m in claude_plugins.load_plugin_agents(install_path)] if installed else [],
                "hooks":  [{"event": h.event, "matcher": h.matcher, "actions": h.actions}
                           for h in claude_plugins.load_plugin_hooks(install_path)] if installed else [],
            })
        return rows
    return {s: section(s) for s in ("local", "project", "user")}


def load_known_marketplaces() -> list[dict]:
    """
    Reads ~/.claude/plugins/known_marketplaces.json.
    Returns list of { "key", "installLocation", "lastUpdated" } dicts.
    Returns [] if file is missing.
    """
    if not MARKETPLACES_JSON.exists():
        return []
    raw = json.loads(MARKETPLACES_JSON.read_text(encoding="utf-8"))
    result = []
    for key, info in raw.items():
        result.append({
            "key": key,
            "installLocation": info.get("installLocation", ""),
            "lastUpdated": info.get("lastUpdated", ""),
        })
    return result


def load_marketplace_plugins(marketplace_key: str, install_location: str) -> tuple[list, object]:
    """
    Reads <install_location>/.claude-plugin/marketplace.json.
    Returns (plugins_list, error_string_or_None).
    plugins_list entries: { "name", "description", "version", "author", "keywords" }
    """
    if not install_location:
        return [], "installLocation is empty"
    mp_json = Path(install_location) / ".claude-plugin" / "marketplace.json"
    if not mp_json.exists():
        return [], f"marketplace.json not found at {mp_json}"
    try:
        raw = json.loads(mp_json.read_text(encoding="utf-8"))
    except Exception as e:
        return [], f"Failed to parse marketplace.json: {e}"

    plugins = []
    for p in raw.get("plugins", []):
        plugins.append({
            "name": p.get("name", ""),
            "description": p.get("description", ""),
            "version": p.get("version", ""),
            "author": (p.get("author") or {}).get("name", ""),
            "keywords": p.get("keywords", []),
        })
    return plugins, None


def build_marketplace_response(project_root: Path) -> dict:
    """
    Combines known_marketplaces.json with each marketplace's marketplace.json.
    Per-scope install state is supplied separately via the installedScopes map on
    /api/plugins (ITER_17); the frontend uses that to decide install/installed per scope.
    """
    marketplaces_meta = load_known_marketplaces()
    if not marketplaces_meta:
        return {"marketplaces": [], "error": "known_marketplaces.json not found"}

    result = []
    for m in marketplaces_meta:
        plugins_raw, err = load_marketplace_plugins(m["key"], m["installLocation"])
        entry: dict = {
            "key": m["key"],
            "lastUpdated": m["lastUpdated"],
        }
        if err:
            entry["plugins"] = []
            entry["error"] = err
        else:
            entry["plugins"] = [
                {**p, "marketplace": m["key"], "id": f"{p['name']}@{m['key']}"}
                for p in plugins_raw
            ]
        result.append(entry)

    return {"marketplaces": result}


class SkillsServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        import sys
        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionAbortedError, ConnectionResetError, BrokenPipeError)):
            return
        super().handle_error(request, client_address)

    def __init__(self, server_address, RequestHandlerClass, project_root: Path):
        super().__init__(server_address, RequestHandlerClass)
        self.project_root = project_root
        self.sse_clients: list[queue.Queue] = []
        self.sse_clients_lock = threading.Lock()
        self._watch_mtimes: dict[str, object] = {}
        self._start_watcher()

    def _watched_paths(self) -> list[Path]:
        return [
            PLUGINS_BASE / "installed_plugins.json",
            Path.home() / ".claude" / "settings.json",                    # user
            Path(self.project_root) / ".claude" / "settings.json",        # project
            Path(self.project_root) / ".claude" / "settings.local.json",  # local
        ]

    def _start_watcher(self) -> None:
        for p in self._watched_paths():
            self._watch_mtimes[str(p)] = p.stat().st_mtime if p.exists() else None
        self._schedule_watch()

    def _schedule_watch(self) -> None:
        t = threading.Timer(1.0, self._poll)
        t.daemon = True
        t.start()

    def _poll(self) -> None:
        changed = False
        for p in self._watched_paths():
            key = str(p)
            try:
                mtime = p.stat().st_mtime if p.exists() else None
            except OSError:
                mtime = None
            if mtime != self._watch_mtimes.get(key):
                self._watch_mtimes[key] = mtime
                changed = True
        if changed:
            self._broadcast_refresh()
        self._schedule_watch()

    def _broadcast_refresh(self) -> None:
        with self.sse_clients_lock:
            dead = []
            for q in self.sse_clients:
                try:
                    q.put_nowait("refresh")
                except Exception:
                    dead.append(q)
            for q in dead:
                self.sse_clients.remove(q)

    def add_sse_client(self, q: queue.Queue) -> None:
        with self.sse_clients_lock:
            self.sse_clients.append(q)

    def remove_sse_client(self, q: queue.Queue) -> None:
        with self.sse_clients_lock:
            if q in self.sse_clients:
                self.sse_clients.remove(q)


class RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress default request logging

    def _send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "http://localhost")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length))

    def _serve_file(self, filename: str, content_type: str):
        path = Path(__file__).parent / filename
        if not path.exists():
            self.send_response(404)
            self.end_headers()
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "http://localhost")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/":
            self._serve_file("index.html", "text/html")

        elif self.path == "/styles.css":
            self._serve_file("styles.css", "text/css")

        elif self.path == "/icon.svg":
            self._serve_file("icon.svg", "image/svg+xml")

        elif self.path.startswith("/js/") and self.path.endswith(".js"):
            # Basename only — flattens any traversal attempt; js/ is a flat directory.
            self._serve_file(f"js/{self.path.rsplit('/', 1)[-1]}", "text/javascript")

        elif self.path == "/api/plugins":
            project_root = self.server.project_root
            try:
                raw = load_installed_plugins(project_root)
                is_mock = raw.pop("mock", False)
                settings = {
                    "local":   load_settings_local(project_root).get("enabledPlugins", {}),
                    "project": load_settings_project(project_root).get("enabledPlugins", {}),
                    "user":    load_settings_user().get("enabledPlugins", {}),
                }
                sections = build_sections(raw, settings)
            except ValueError as exc:
                failed_path = str(exc)
                self._send_json(
                    {"error": f"Failed to parse {failed_path}", "path": failed_path}, 500
                )
                return

            # Per-id installed-scopes map for the marketplace panel (ITER_17)
            installed_scopes: dict[str, list[str]] = {}
            for scope in ("local", "project", "user"):
                for p in sections[scope]:
                    if p["installed"]:
                        installed_scopes.setdefault(p["id"], []).append(scope)

            payload = {
                **sections,
                "installedScopes": installed_scopes,
                "project_root": str(project_root),
            }
            if is_mock:
                payload["mock"] = True
            self._send_json(payload)

        elif self.path == "/api/marketplace":
            payload = build_marketplace_response(self.server.project_root)
            self._send_json(payload)

        elif self.path == "/api/events":
            q: queue.Queue = queue.Queue()
            self.server.add_sse_client(q)

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            try:
                self.wfile.write(b"data: connected\n\n")
                self.wfile.flush()
                while True:
                    try:
                        msg = q.get(timeout=15)
                        self.wfile.write(f"data: {msg}\n\n".encode())
                        self.wfile.flush()
                    except queue.Empty:
                        # Send SSE comment as keepalive to prevent proxy/browser timeouts
                        self.wfile.write(b": keepalive\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass
            finally:
                self.server.remove_sse_client(q)

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/toggle":
            body = self._read_body()
            plugin_id = body.get("id", "")
            enabled = body.get("enabled")
            scope = body.get("scope", "")

            if "@" not in plugin_id:
                self._send_json({"ok": False, "error": "Invalid plugin id format"}, 400)
                return
            if scope not in ("local", "project", "user"):
                self._send_json(
                    {"ok": False, "error": "scope must be local, project, or user"}, 400
                )
                return
            if not isinstance(enabled, bool):
                self._send_json({"ok": False, "error": "enabled must be a boolean"}, 400)
                return

            root = self.server.project_root

            def read_scope(s):
                if s == "local":   return load_settings_local(root)
                if s == "project": return load_settings_project(root)
                return load_settings_user()

            def write_scope(s, settings):
                if s == "local":     save_settings_local(root, settings)
                elif s == "project": save_settings_project(root, settings)
                else:                save_settings_user(settings)

            # Guard: the id must belong to this scope's section (registry-at-scope ∪ settings-at-scope)
            raw = load_installed_plugins(root)
            raw.pop("mock", None)
            installed_ids = {e["id"] for e in raw.get(scope, [])}
            settings = read_scope(scope)
            section_ids = installed_ids | set(settings.get("enabledPlugins", {}))
            if plugin_id not in section_ids:
                self._send_json(
                    {"ok": False, "error": f"{plugin_id} is not present in {scope} scope"}, 400
                )
                return

            settings.setdefault("enabledPlugins", {})[plugin_id] = enabled
            write_scope(scope, settings)
            self._send_json({"ok": True})

        elif self.path == "/api/set-project":
            body = self._read_body()
            path_str = body.get("path", "")
            if not os.path.isdir(path_str):
                self._send_json(
                    {"ok": False, "error": f"Path does not exist: {path_str}"}, 400
                )
                return
            self.server.project_root = Path(path_str)
            # Re-seed the watcher so it picks up the new project's settings file
            self.server._watch_mtimes = {}
            self._send_json({"ok": True, "project_root": path_str})

        elif self.path == "/api/install-stream":
            body = self._read_body()
            plugin_id = body.get("id", "")
            scope = body.get("scope", "local")

            if "@" not in plugin_id:
                self._send_json({"ok": False, "error": "Invalid plugin id format"}, 400)
                return
            if scope not in ("local", "project", "user"):
                self._send_json(
                    {"ok": False, "error": "scope must be local, project, or user"}, 400
                )
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            def send_event(payload: dict):
                line = json.dumps(payload, ensure_ascii=False)
                self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                self.wfile.flush()

            try:
                proc = subprocess.Popen(
                    ["claude", "plugin", "install", plugin_id, "--scope", scope],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=self.server.project_root,
                )
            except FileNotFoundError:
                send_event({"type": "done", "ok": False, "error": "'claude' CLI not found on PATH"})
                return

            try:
                for raw_line in iter(proc.stdout.readline, b""):
                    text = raw_line.decode("utf-8", errors="replace")
                    send_event({"type": "line", "text": text})
            except (BrokenPipeError, ConnectionResetError):
                proc.kill()
                proc.wait()
                return

            proc.wait()

            if proc.returncode == 0:
                send_event({"type": "done", "ok": True})
            else:
                send_event({"type": "done", "ok": False, "error": f"Exit code {proc.returncode}"})

        elif self.path == "/api/uninstall-stream":
            body = self._read_body()
            plugin_id = body.get("id", "")
            scope     = body.get("scope", "")

            if "@" not in plugin_id:
                self._send_json({"ok": False, "error": "Invalid plugin id format"}, 400)
                return
            if scope not in ("local", "user", "project"):
                self._send_json({"ok": False, "error": "scope must be 'local', 'user', or 'project'"}, 400)
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            def send_event(payload: dict):
                line = json.dumps(payload, ensure_ascii=False)
                self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                self.wfile.flush()

            try:
                proc = subprocess.Popen(
                    ["claude", "plugin", "uninstall", plugin_id, "--scope", scope],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=self.server.project_root,
                )
            except FileNotFoundError:
                send_event({"type": "done", "ok": False, "error": "'claude' CLI not found on PATH"})
                return

            try:
                for raw_line in iter(proc.stdout.readline, b""):
                    text = raw_line.decode("utf-8", errors="replace")
                    send_event({"type": "line", "text": text})
            except (BrokenPipeError, ConnectionResetError):
                proc.kill()
                proc.wait()
                return

            proc.wait()

            if proc.returncode == 0:
                send_event({"type": "done", "ok": True})
            else:
                send_event({"type": "done", "ok": False, "error": f"Exit code {proc.returncode}"})

        elif self.path == "/api/marketplace-refresh":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            def send_event(payload: dict):
                line = json.dumps(payload, ensure_ascii=False)
                self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                self.wfile.flush()

            try:
                proc = subprocess.Popen(
                    ["claude", "plugin", "marketplace", "update"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=self.server.project_root,
                )
            except FileNotFoundError:
                send_event({"type": "done", "ok": False, "error": "'claude' CLI not found on PATH"})
                return

            try:
                for raw_line in iter(proc.stdout.readline, b""):
                    text = raw_line.decode("utf-8", errors="replace")
                    send_event({"type": "line", "text": text})
            except (BrokenPipeError, ConnectionResetError):
                proc.kill()
                proc.wait()
                return

            proc.wait()

            if proc.returncode == 0:
                send_event({"type": "done", "ok": True})
            else:
                send_event({"type": "done", "ok": False, "error": f"Exit code {proc.returncode}"})

        elif self.path == "/api/shutdown":
            self._send_json({"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()

        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7779
    project_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(os.getcwd())
    server = SkillsServer(("127.0.0.1", port), RequestHandler, project_root)
    print(f"Serving at http://127.0.0.1:{port}  (project root: {project_root})")
    server.serve_forever()
