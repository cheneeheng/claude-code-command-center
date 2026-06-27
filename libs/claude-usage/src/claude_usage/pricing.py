"""Model pricing and estimated-cost computation for Claude Code usage."""

from __future__ import annotations

# Per 1M tokens: (input, output, cache_write, cache_read).
MODEL_COSTS: dict[str, tuple[float, float, float, float]] = {
    "claude-fable": (10.00, 50.00, 12.50, 1.00),
    "claude-opus": (15.00, 75.00, 18.75, 1.50),
    "claude-sonnet": (3.00, 15.00, 3.75, 0.30),
    "claude-haiku": (0.80, 4.00, 1.00, 0.08),
}

# Token counts for one model: keys ``input``, ``output``, ``cache_write``, ``cache_read``.
TokenCounts = dict[str, int]


def model_family(model_id: str) -> str:
    """Collapse a raw model id to its pricing-family key.

    Different versions (e.g. ``claude-opus-4-7`` and ``claude-opus-4-8``) map to
    the same family so they aggregate and cost out as one model.

    Args:
        model_id: The raw model identifier from a transcript.

    Returns:
        The matching family key, or ``model_id`` unchanged if none matches.
    """
    m = (model_id or "").lower()
    for key in MODEL_COSTS:
        if key.split("-")[1] in m:
            return key
    return model_id


def model_costs(model_id: str) -> tuple[float, float, float, float] | None:
    """Return the per-1M-token price tuple for a model, or ``None`` if unknown."""
    return MODEL_COSTS.get(model_family(model_id))


def estimated_cost(per_model: dict[str, TokenCounts]) -> float:
    """Estimate USD cost from per-model token counts and the pricing table.

    This is an estimate (tokens x list price), not the amount Anthropic billed.

    Args:
        per_model: Mapping of model id to its token counts
            (``input``, ``output``, ``cache_write``, ``cache_read``).

    Returns:
        The estimated cost in USD.
    """
    cost = 0.0
    for model_id, tok in per_model.items():
        costs = model_costs(model_id)
        if not costs:
            continue
        inp_c, out_c, cw_c, cr_c = costs
        cost += (tok["input"] / 1_000_000) * inp_c
        cost += (tok["output"] / 1_000_000) * out_c
        cost += (tok["cache_write"] / 1_000_000) * cw_c
        cost += (tok["cache_read"] / 1_000_000) * cr_c
    return cost
