"""Command line: ``usage-insights`` (serve the dashboard) and ``usage-insights export``."""

from __future__ import annotations

import argparse
import urllib.request
import webbrowser
from pathlib import Path

from claude_usage import claude_dirs

from usage_insights import export, server, store

DEFAULT_PORT = 8090


def _parser() -> argparse.ArgumentParser:
    dirs = argparse.ArgumentParser(add_help=False)
    dirs.add_argument(
        "--claude-dir",
        action="append",
        type=Path,
        # No default: the export subparser would otherwise reset a value given before it.
        default=argparse.SUPPRESS,
        help="Claude config dir to read (repeatable). Default: $C4_CLAUDE_DIR or ~/.claude",
    )
    parser = argparse.ArgumentParser(prog="usage-insights", parents=[dirs])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--no-open", action="store_true", help="do not open the browser")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser(
        "export", parents=[dirs], help="copy new and changed transcripts into the store"
    )
    return parser


def _export(db: Path, dirs: list[Path]) -> None:
    try:
        result = export.run_export(db, dirs, store.LOCK_TIMEOUT)
    except store.ExportBusy:
        print("export already running")
        return
    print(
        f"files scanned {result.files_scanned}, files parsed {result.files_parsed}, "
        f"messages {result.messages}, events {result.events}"
    )


def _running(host: str, port: int) -> bool:
    """Whether a usage-insights instance answers ``/api/health`` on the port."""
    req = urllib.request.Request(f"http://{host}:{port}/api/health")
    req.add_header("Host", f"{host}:{port}")
    try:
        with urllib.request.urlopen(req, timeout=1) as resp:
            return bool(resp.status == 200 and b'"ok": true' in resp.read())
    except OSError:
        return False


def main(argv: list[str] | None = None) -> int:
    """Run the command line and return its exit code."""
    args = _parser().parse_args(argv)
    dirs: list[Path] = getattr(args, "claude_dir", None) or claude_dirs()
    db = store.store_path()
    _export(db, dirs)
    if args.command == "export":
        return 0

    url = f"http://{args.host}:{args.port}/"
    try:
        httpd = server.make_server(args.host, args.port, db, dirs)
    except OSError:
        if _running(args.host, args.port):
            if not args.no_open:
                webbrowser.open(url)
            return 0
        print(f"port {args.port} is in use by another program; pass --port to pick another")
        return 1
    print(f"usage-insights serving {url} (Ctrl+C to stop)")
    if not args.no_open:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0
