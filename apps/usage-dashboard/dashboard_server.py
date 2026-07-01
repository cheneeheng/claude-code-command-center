"""HTTP handler: serves the static dashboard assets and the /api/data payload.

The JSON payload itself is assembled in merge.py, which reconciles the two data
sources (session_stats + live_statusline). This module is transport only."""

import json
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler

from merge import build_payload

_ASSET_DIR = Path(__file__).parent

# The CSS and JS are split into small, single-concern source files under css/ and
# js/ for readability, then concatenated in load order into one response each. The
# JS parts are plain (non-module) scripts sharing one global scope, so order is the
# concatenation order and the bootstrap part (app.js) must come last.
_CSS_PARTS = ["css/tokens.css", "css/base.css", "css/components.css", "css/controls.css"]
_JS_PARTS = [
    "js/format.js",
    "js/models.js",
    "js/charts.js",
    "js/rate-limit.js",
    "js/render.js",
    "js/settings.js",
    "js/app.js",
]


def _bundle(parts: list[str]) -> str:
    return "\n".join((_ASSET_DIR / p).read_text(encoding="utf-8") for p in parts)


HTML = (_ASSET_DIR / "dashboard.html").read_text(encoding="utf-8")
CSS = _bundle(_CSS_PARTS)
JS = _bundle(_JS_PARTS)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress request logs

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/" or parsed.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(HTML.encode("utf-8"))

        elif parsed.path == "/dashboard.css":
            self.send_response(200)
            self.send_header("Content-Type", "text/css; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(CSS.encode("utf-8"))

        elif parsed.path == "/dashboard.js":
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(JS.encode("utf-8"))

        elif parsed.path == "/api/data":
            try:
                qs = parse_qs(parsed.query)
                live_timeout = None
                if "live_timeout" in qs:
                    try:
                        live_timeout = max(1, int(qs["live_timeout"][0]))
                    except (ValueError, IndexError):
                        pass
                payload = json.dumps(build_payload(live_timeout))
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(payload.encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        else:
            self.send_response(404)
            self.end_headers()
