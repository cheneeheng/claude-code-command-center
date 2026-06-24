"""Configuration and model-pricing helpers for the usage dashboard."""

import os
from pathlib import Path


def _default_claude_dirs() -> list[Path]:
    env = os.environ.get("CLAUDE_DIR", "")
    if env:
        return [Path(p) for p in env.split(os.pathsep) if p.strip()]
    return [Path.home() / ".claude"]


CLAUDE_DIRS: list[Path] = _default_claude_dirs()

# Sessions with no statusline update in this window are considered inactive.
LIVE_SESSION_TIMEOUT_SECS: int = int(os.environ.get("STATUSLINE_LIVE_TIMEOUT", 1800))  # 30 min

MODEL_COSTS = {
    # per 1M tokens: (input_cost, output_cost, cache_write_cost, cache_read_cost)
    "claude-fable":   (10.00,  50.00, 12.50,  1.00),
    "claude-opus":    (15.00,  75.00, 18.75,  1.50),
    "claude-sonnet":  ( 3.00,  15.00,  3.75,  0.30),
    "claude-haiku":   ( 0.80,   4.00,  1.00,  0.08),
}


def model_family(model_id: str) -> str:
    """Collapse a raw model id to its family key so different versions
    (e.g. claude-opus-4-7 and claude-opus-4-8) aggregate as one model."""
    m = (model_id or "").lower()
    for key in MODEL_COSTS:
        if key.split("-")[1] in m:
            return key
    return model_id


def model_costs(model_id: str):
    fam = model_family(model_id)
    return MODEL_COSTS.get(fam)
