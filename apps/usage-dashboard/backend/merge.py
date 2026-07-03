"""Assemble the single /api/data payload from the two data sources.

The dashboard draws on two independent sources:

    session_stats.py   historical transcripts -> token totals + ESTIMATED cost
    live_statusline.py live statusline logs   -> rate limits (+ informational cost)

In v4 the pricing-table estimate is CANONICAL for every aggregate and every
session row: there is no cost overlay. The statusline's actual per-session cost
(`live.sessions[].session_cost`) remains visible only in the live rate-limit card
— informational, never merged into `stats` or `sessions`.
"""

import dashboard_config
from session_stats import load_cached, scope_sessions, summarize_sessions
from live_statusline import read_statusline


def build_payload(
    live_timeout: int | None,
    range_key: str = "all",
    project: str | None = None,
) -> dict:
    """Assemble the full /api/data payload: stats, sessions, and live rate limits.

    ``stats`` are range/project-scoped aggregates; ``sessions`` is the matching
    scoped row set (the table shows what the cards count)."""
    rows, activity = load_cached()
    live = read_statusline(timeout=live_timeout)
    live["timeout"] = (live_timeout if live_timeout is not None
                       else dashboard_config.LIVE_SESSION_TIMEOUT_SECS)

    stats = summarize_sessions(rows, activity, range_key, project)
    scoped = scope_sessions(rows, range_key, project)

    # `per_model` is an internal aggregation detail; strip it before sending.
    sessions_out = [{k: v for k, v in s.items() if k != "per_model"} for s in scoped]
    return {"stats": stats, "sessions": sessions_out, "live": live}
