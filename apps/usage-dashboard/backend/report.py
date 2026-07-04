"""Render the /api/report.md Markdown usage report from a built payload.

No new aggregation: this reads the same ``{stats, sessions, live}`` that
merge.build_payload produces and formats it as Markdown (stdlib f-strings only).
Cost is the pricing-table estimate, canonical throughout (see merge.py).
"""

from datetime import datetime


def _usd(n: float) -> str:
    return f"${n:,.2f}"


def _int(n: int) -> str:
    return f"{n:,}"


def _pct(v: float | None) -> str:
    return "—" if v is None else f"{v:+.0f}%"


def render_report(payload: dict, range_key: str, project: str | None) -> str:
    """Format a build_payload result as a Markdown usage report."""
    stats = payload["stats"]
    scope = f"Range: `{range_key}`"
    if project:
        scope += f" · Project: `{project}`"

    out: list[str] = [
        "# Claude Code Usage Report",
        "",
        f"_Generated {datetime.now().astimezone():%Y-%m-%d %H:%M %Z}_",
        "",
        scope,
        "",
        "## Totals",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Sessions | {_int(stats['total_sessions'])} |",
        f"| Total tokens | {_int(stats['total_tokens'])} |",
        f"| Input | {_int(stats['total_input'])} |",
        f"| Output | {_int(stats['total_output'])} |",
        f"| Cache write | {_int(stats['total_cache_write'])} |",
        f"| Cache read | {_int(stats['total_cache_read'])} |",
        f"| Est. cost | {_usd(stats['total_cost_usd'])} |",
        f"| Cache savings | {_usd(stats['cache_savings_usd'])} |",
    ]

    delta = stats.get("delta")
    if delta:
        out.append(f"| Δ tokens vs prev | {_pct(delta['tokens_pct'])} |")
        out.append(f"| Δ cost vs prev | {_pct(delta['cost_pct'])} |")
    out.append("")

    plan = stats.get("plan")
    if plan:
        out += [
            "## Plan Value",
            "",
            f"- {_usd(plan['month_value_usd'])} of usage on a "
            f"{_usd(plan['price_usd'])} plan (**{plan['ratio']:.1f}×**)",
            "",
        ]

    if stats.get("by_project"):
        out += ["## Top Projects", "", "| Project | Tokens | Est. cost |", "|---|---|---|"]
        out += [f"| {p['project']} | {_int(p['tokens'])} | {_usd(p['cost'])} |"
                for p in stats["by_project"]]
        out.append("")

    if stats.get("by_model"):
        out += ["## By Model", "", "| Model | Tokens | Est. cost |", "|---|---|---|"]
        out += [f"| {m['model']} | {_int(m['tokens'])} | {_usd(m['cost'])} |"
                for m in stats["by_model"]]
        out.append("")

    if stats.get("top_sessions"):
        out += ["## Top Sessions by Cost", "", "| Session | Project | Est. cost |", "|---|---|---|"]
        out += [f"| {s['session_id']} | {s['project']} | {_usd(s['cost_usd'])} |"
                for s in stats["top_sessions"]]
        out.append("")

    if stats.get("tools"):
        out += ["## Top Tools", "", "| Tool | Calls |", "|---|---|"]
        out += [f"| {t['name']} | {_int(t['count'])} |" for t in stats["tools"][:10]]
        out.append("")

    return "\n".join(out) + "\n"
