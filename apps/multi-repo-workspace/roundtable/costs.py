"""Result-event usage -> per-model token counts -> claude_usage.estimated_cost.

Cost policy (SKELETON_v5 §06, inherited from the usage-dashboard v4 decision): the
pricing-table estimate is canonical; the CLI's `total_cost_usd` is stored as
`cost_reported_usd` and shown only as an informational secondary figure. A model
missing from the pricing table yields `cost_est_usd: None`, rendered "n/a", never 0.
"""

from __future__ import annotations

from typing import Any

from claude_usage import estimated_cost, model_costs

# (canonical key, [event-key aliases]) — modelUsage uses camelCase, usage snake_case.
_KEY_ALIASES: list[tuple[str, list[str]]] = [
    ("input", ["input_tokens", "inputTokens"]),
    ("output", ["output_tokens", "outputTokens"]),
    ("cache_write", ["cache_creation_input_tokens", "cacheCreationInputTokens"]),
    ("cache_read", ["cache_read_input_tokens", "cacheReadInputTokens"]),
]


def _counts(raw: dict[str, Any]) -> dict[str, int]:
    """Normalize one usage block onto claude-usage's TokenCounts keys."""
    out: dict[str, int] = {}
    for canonical, aliases in _KEY_ALIASES:
        value = 0
        for key in aliases:
            if isinstance(raw.get(key), (int, float)):
                value = int(raw[key])
                break
        out[canonical] = value
    return out


def extract(result_event: dict[str, Any], fallback_model: str | None) -> dict[str, Any]:
    """{usage, cost_est_usd, cost_reported_usd} from a stream-json `result` event.

    Prefers per-model `modelUsage`; falls back to `{fallback_model: usage}` (fallback
    model = the resolved --model knob, else the init event's model). Any model absent
    from the pricing table makes the estimate None rather than silently partial.
    """
    per_model: dict[str, dict[str, int]] = {}
    model_usage = result_event.get("modelUsage")
    if isinstance(model_usage, dict) and model_usage:
        for model, block in model_usage.items():
            if isinstance(block, dict):
                per_model[str(model)] = _counts(block)
    elif isinstance(result_event.get("usage"), dict) and fallback_model:
        per_model[fallback_model] = _counts(result_event["usage"])

    cost_est: float | None
    if per_model and all(model_costs(m) is not None for m in per_model):
        cost_est = estimated_cost(per_model)
    else:
        cost_est = None

    reported = result_event.get("total_cost_usd")
    return {
        "usage": per_model or None,
        "cost_est_usd": cost_est,
        "cost_reported_usd": float(reported)
        if isinstance(reported, (int, float))
        else None,
    }
