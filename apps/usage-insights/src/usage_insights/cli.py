"""Command line: ``usage-insights export``."""

from __future__ import annotations

import argparse
from pathlib import Path

from usage_insights import export, store


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="usage-insights")
    sub = parser.add_subparsers(dest="command", required=True)
    exp = sub.add_parser("export", help="copy new and changed transcripts into the store")
    exp.add_argument(
        "--claude-dir",
        action="append",
        type=Path,
        help="Claude config dir to read (repeatable). Default: $C4_CLAUDE_DIR or ~/.claude",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the command line and return its exit code."""
    args = _parser().parse_args(argv)
    try:
        result = export.run_export(store.store_path(), args.claude_dir, store.LOCK_TIMEOUT)
    except store.ExportBusy:
        print("export already running")
        return 0
    print(
        f"files scanned {result.files_scanned}, files parsed {result.files_parsed}, "
        f"messages {result.messages}, events {result.events}"
    )
    return 0
