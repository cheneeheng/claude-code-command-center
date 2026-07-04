"""HTTP handler: serves the static dashboard assets and the /api/data payload.

The JSON payload itself is assembled in merge.py, which reconciles the two data
sources (session_stats + live_statusline). This module is transport only."""

import csv
import io
import json
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler

import dashboard_config
from merge import build_payload
from live_statusline import read_statusline
from report import render_report

_ASSET_DIR = Path(__file__).parent.parent / "web"

# The CSS and JS are split into small, single-concern source files under css/ and
# js/ for readability, then concatenated in load order into one response each. The
# JS parts are plain (non-module) scripts sharing one global scope, so order is the
# concatenation order and the bootstrap part (app.js) must come last.
_CSS_PARTS = ["css/tokens.css", "css/base.css", "css/components.css", "css/controls.css"]
_JS_PARTS = [
    "js/format.js",
    "js/models.js",
    "js/charts.js",
    "js/heatmap.js",
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

_CSV_COLUMNS = [
    "session_id", "project", "models", "input_tokens", "output_tokens",
    "cache_write_tokens", "cache_read_tokens", "total_tokens", "cost_usd",
    "duration_secs", "cost_per_hour", "cache_hit_pct",
    "message_count", "first_ts", "last_ts",
]


def _scope_params(qs: dict) -> tuple[str, str | None]:
    """Extract (range_key, project) from a parsed query string."""
    range_key = qs.get("range", ["all"])[0]
    project = qs.get("project", [None])[0]
    return range_key, project


def _sessions_csv(sessions: list[dict]) -> str:
    """Render the per-session rows as CSV (models joined with ';')."""
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(_CSV_COLUMNS)
    for s in sessions:
        row = {**s, "models": ";".join(s.get("models") or [])}
        writer.writerow(row.get(c, "") for c in _CSV_COLUMNS)
    return buf.getvalue()


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

        elif parsed.path == "/api/export.csv":
            try:
                range_key, project = _scope_params(parse_qs(parsed.query))
                body = _sessions_csv(build_payload(None, range_key, project)["sessions"])
                self.send_response(200)
                self.send_header("Content-Type", "text/csv; charset=utf-8")
                self.send_header(
                    "Content-Disposition",
                    'attachment; filename="claude-code-usage.csv"',
                )
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(body.encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        elif parsed.path == "/api/live":
            # Cheap fast-poll: statusline only, no transcript parse or build_payload.
            try:
                qs = parse_qs(parsed.query)
                live_timeout = None
                if "live_timeout" in qs:
                    try:
                        live_timeout = max(1, int(qs["live_timeout"][0]))
                    except (ValueError, IndexError):
                        pass
                live = read_statusline(timeout=live_timeout)
                live["timeout"] = (live_timeout if live_timeout is not None
                                   else dashboard_config.LIVE_SESSION_TIMEOUT_SECS)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(json.dumps(live).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        elif parsed.path == "/api/report.md":
            try:
                range_key, project = _scope_params(parse_qs(parsed.query))
                payload = build_payload(None, range_key, project)
                body = render_report(payload, range_key, project)
                self.send_response(200)
                self.send_header("Content-Type", "text/markdown; charset=utf-8")
                self.send_header(
                    "Content-Disposition",
                    'attachment; filename="claude-code-usage-report.md"',
                )
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(body.encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())

        elif parsed.path == "/api/data":
            try:
                qs = parse_qs(parsed.query)
                live_timeout = None
                if "live_timeout" in qs:
                    try:
                        live_timeout = max(1, int(qs["live_timeout"][0]))
                    except (ValueError, IndexError):
                        pass
                range_key, project = _scope_params(qs)
                payload = json.dumps(build_payload(live_timeout, range_key, project))
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
