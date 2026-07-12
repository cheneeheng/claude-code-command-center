"""CLI dispatch: `roundtable serve | init | doctor`."""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="roundtable", description=__doc__)
    parser.add_argument("--registry", help="path to .roundtable.json")
    sub = parser.add_subparsers(dest="command")

    serve = sub.add_parser("serve", help="launch the localhost browser server")
    # default None -> run_server falls back to Config.port; an explicit flag wins.
    serve.add_argument("--port", type=int, default=None)

    init = sub.add_parser("init", help="generate or update .roundtable.json")
    init.add_argument(
        "--scan", metavar="ROOT", help="discover repos with a planning dir under ROOT"
    )
    init.add_argument(
        "--output",
        default=".roundtable.json",
        help="output path (default ./.roundtable.json)",
    )
    mode = init.add_mutually_exclusive_group()
    mode.add_argument("--force", action="store_true", help="overwrite an existing file")
    mode.add_argument(
        "--merge", action="store_true", help="add only newly-found repos in place"
    )
    init.add_argument(
        "--dry-run", action="store_true", help="print the result without writing"
    )

    sub.add_parser("doctor", help="check the registry for problems")

    args = parser.parse_args(argv)

    if args.command == "serve":
        from roundtable.server import run_server

        return run_server(port=args.port, registry_path=args.registry)
    if args.command == "init":
        from roundtable import registry

        try:
            print(
                registry.cmd_init(
                    output=args.output,
                    scan=args.scan,
                    force=args.force,
                    merge=args.merge,
                    dry_run=args.dry_run,
                )
            )
        except (FileExistsError, FileNotFoundError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        return 0
    if args.command == "doctor":
        from roundtable import registry

        return registry.cmd_doctor(args.registry)

    parser.print_help()
    return 1
