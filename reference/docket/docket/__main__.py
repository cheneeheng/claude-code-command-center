"""CLI dispatch: `docket tui | serve | init | doctor`."""

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="docket", description=__doc__)
    parser.add_argument("--registry", help="path to .docket.json")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("tui", help="launch the Textual terminal UI")

    serve = sub.add_parser("serve", help="launch the localhost browser server")
    # default None -> run_server falls back to Config.port; an explicit flag wins.
    serve.add_argument("--port", type=int, default=None)

    init = sub.add_parser("init", help="generate or update .docket.json")
    init.add_argument(
        "--scan", metavar="ROOT", help="discover repos with a planning dir under ROOT"
    )
    init.add_argument(
        "--output", default=".docket.json", help="output path (default ./.docket.json)"
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

    if args.command == "tui":
        from docket.tui import run_tui

        return run_tui(registry=args.registry)
    if args.command == "serve":
        from docket.server import run_server

        return run_server(port=args.port, registry=args.registry)
    if args.command == "init":
        from docket import core

        try:
            print(
                core.cmd_init(
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
        from docket import core

        return core.cmd_doctor(args.registry)

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
