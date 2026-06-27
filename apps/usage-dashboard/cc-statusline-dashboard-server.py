#!/usr/bin/env python3
"""
Claude Code Token Usage Dashboard
----------------------------------
Reads ~/.claude/projects/**/*.jsonl and serves a live dashboard on localhost:8080.
No pip install. No dependencies. Pure stdlib.

Usage:
    python3 cc-statusline-dashboard-server.py
    python3 cc-statusline-dashboard-server.py --port 9000
    python3 cc-statusline-dashboard-server.py --host 0.0.0.0 --port 8080
    python3 cc-statusline-dashboard-server.py --claude-dir ~/.claude ~/work/.claude

Module layout:
    claude-usage (lib)   - transcript parsing + pricing (load_sessions, estimated_cost)
    dashboard_config.py  - runtime config (CLAUDE_DIRS, live-session timeout)
    session_stats.py     - source 1: session usage (via claude-usage) -> tokens + estimated cost
    live_statusline.py   - source 2: statusline logs -> rate limits + actual cost
    merge.py             - reconcile the two sources into the /api/data payload
    dashboard_server.py  - HTTP handler (serves assets + payload)
    dashboard.{html,css,js} - dashboard UI
See README.md for the full data-flow and provenance notes.
"""

import sys
import argparse
from pathlib import Path
from http.server import HTTPServer

# Ensure sibling modules are importable when launched by absolute path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import dashboard_config
from live_statusline import trim_statusline_logs
from dashboard_server import Handler


def main():
    parser = argparse.ArgumentParser(description="Claude Code Token Usage Dashboard")
    parser.add_argument("--host", default="localhost", help="Bind host (default: localhost)")
    parser.add_argument("--port", type=int, default=8080, help="Port (default: 8080)")
    parser.add_argument("--claude-dir", nargs="+", default=None,
                        help="One or more Claude config dirs (default: ~/.claude). "
                             "All projects are aggregated as if they were one.")
    args = parser.parse_args()

    if args.claude_dir:
        dashboard_config.CLAUDE_DIRS = [Path(d) for d in args.claude_dir]

    missing = [str(d / "projects") for d in dashboard_config.CLAUDE_DIRS
               if not (d / "projects").exists()]
    for m in missing:
        print(f"⚠  Projects dir not found: {m}")

    trim_statusline_logs()  # trim on startup; won't run again until next restart

    server = HTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}"
    print("  Claude Code Usage Dashboard")
    for d in dashboard_config.CLAUDE_DIRS:
        print(f"  Watching: {d / 'projects'}")
    print(f"  Open:     {url}")
    print("  Stop:     Ctrl+C\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")


if __name__ == "__main__":
    main()
