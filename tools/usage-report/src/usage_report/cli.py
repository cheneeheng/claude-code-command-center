"""CLI: summarise Claude Code token usage and estimated cost across sessions."""

from __future__ import annotations

import argparse
from collections import defaultdict

from claude_usage import Session, estimated_cost, load_sessions


def _fmt_tokens(n: int) -> str:
    """Render a token count compactly (e.g. ``1.2M``, ``345K``)."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}K"
    return str(n)


def _top_projects(sessions: list[Session], top: int) -> list[tuple[str, int, float]]:
    """Aggregate (tokens, cost) by project, ranked by cost descending."""
    buckets: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0])
    for s in sessions:
        buckets[s.project or "unknown"][0] += s.total_tokens
        buckets[s.project or "unknown"][1] += s.cost_usd
    ranked = sorted(buckets.items(), key=lambda kv: kv[1][1], reverse=True)
    return [(p, int(v[0]), v[1]) for p, v in ranked[:top]]


def _by_model(sessions: list[Session]) -> list[tuple[str, int, float]]:
    """Aggregate (tokens, estimated cost) per model, ranked by cost descending."""
    buckets: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0])
    for s in sessions:
        for model, tok in s.per_model.items():
            buckets[model][0] += sum(tok.values())
            buckets[model][1] += estimated_cost({model: tok})
    ranked = sorted(buckets.items(), key=lambda kv: kv[1][1], reverse=True)
    return [(m, int(v[0]), v[1]) for m, v in ranked]


def _print_table(title: str, rows: list[tuple[str, int, float]], label_w: int) -> None:
    """Print a titled ``label | tokens | $cost`` table."""
    print(f"\n{title}")
    for label, tokens, cost in rows:
        print(f"  {label[:label_w].ljust(label_w)}  {_fmt_tokens(tokens).rjust(7)}  ${cost:>9.2f}")


def main() -> None:
    """Entry point for the ``usage-report`` command."""
    parser = argparse.ArgumentParser(
        prog="usage-report",
        description="Summarise Claude Code token usage and estimated cost.",
    )
    parser.add_argument(
        "--top", type=int, default=5, help="rows to show per ranking (default: 5)"
    )
    args = parser.parse_args()

    sessions = load_sessions()
    if not sessions:
        print("No Claude Code sessions found under ~/.claude/projects.")
        return

    total_tokens = sum(s.total_tokens for s in sessions)
    total_cost = sum(s.cost_usd for s in sessions)
    print(
        f"{len(sessions)} sessions  |  {_fmt_tokens(total_tokens)} tokens  |  "
        f"${total_cost:.2f} estimated"
    )

    top_sessions = [
        (f"{s.session_id} {s.project}", s.total_tokens, s.cost_usd)
        for s in sorted(sessions, key=lambda s: s.cost_usd, reverse=True)[: args.top]
    ]
    _print_table(f"Top {args.top} sessions by cost:", top_sessions, label_w=32)
    _print_table(f"Top {args.top} projects by cost:", _top_projects(sessions, args.top), label_w=32)
    _print_table("By model:", _by_model(sessions), label_w=32)


if __name__ == "__main__":
    main()
