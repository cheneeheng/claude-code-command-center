"""Reconcile the two data sources into the single /api/data payload.

The dashboard draws on two independent sources:

    session_stats.py   historical transcripts -> token totals + ESTIMATED cost
    live_statusline.py live statusline logs   -> rate limits + ACTUAL API cost

They overlap on one field: cost. For a session that is currently live, the
statusline reports the real amount Anthropic billed, which is more accurate than
multiplying tokens by a pricing table. So this module overlays that actual cost
onto the matching session before the summary stats are computed — that single
override is the entire "mix" between the two sources, kept here and nowhere else.
"""

import dashboard_config
from session_stats import load_sessions, summarize_sessions
from live_statusline import read_statusline


def _apply_actual_cost(sessions: list[dict], live: dict) -> None:
    """Replace each live session's estimated cost with the statusline's actual
    API cost, in place. Sessions with no live counterpart keep their estimate."""
    actual_cost = {
        s["session_id"]: s["session_cost"]
        for s in live.get("sessions", [])
        if s.get("session_cost") is not None
    }
    for s in sessions:
        if s["session_id"] in actual_cost:
            s["cost_usd"] = actual_cost[s["session_id"]]


def build_payload(live_timeout: int | None) -> dict:
    """Assemble the full /api/data payload: stats, sessions, and live rate limits."""
    sessions = load_sessions()
    live = read_statusline(timeout=live_timeout)
    live["timeout"] = (live_timeout if live_timeout is not None
                       else dashboard_config.LIVE_SESSION_TIMEOUT_SECS)

    _apply_actual_cost(sessions, live)
    stats = summarize_sessions(sessions)

    # `per_model` is an internal aggregation detail; strip it before sending.
    sessions_out = [{k: v for k, v in s.items() if k != "per_model"} for s in sessions]
    return {"stats": stats, "sessions": sessions_out, "live": live}
