"""Runtime configuration for the usage dashboard.

Transcript parsing and the model pricing table live in the `claude-usage` library;
this module only holds dashboard-specific runtime config. `CLAUDE_DIRS` may be
overridden at startup from the server's `--claude-dir` flag.
"""

import os
from pathlib import Path

import claude_usage

CLAUDE_DIRS: list[Path] = claude_usage.claude_dirs()

# Sessions with no statusline update in this window are considered inactive.
LIVE_SESSION_TIMEOUT_SECS: int = int(os.environ.get("C4_STATUSLINE_LIVE_TIMEOUT", 1800))  # 30 min


def _plan_price() -> float | None:
    """Monthly subscription price from ``C4_PLAN_PRICE_USD`` (invalid/unset -> None)."""
    raw = os.environ.get("C4_PLAN_PRICE_USD", "")
    try:
        price = float(raw)
    except ValueError:
        return None
    return price if price > 0 else None


# Monthly plan price, powering the Plan Value card's ROI ratio. None hides the card.
PLAN_PRICE_USD: float | None = _plan_price()
