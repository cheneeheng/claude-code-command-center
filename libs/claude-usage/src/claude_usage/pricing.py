"""Model pricing and estimated-cost computation for Claude Code usage."""

from __future__ import annotations

from dataclasses import dataclass

# Family fallback, per 1M tokens: (input, output, cache_write, cache_read).
# Used for model versions missing from :data:`MODEL_PRICES`.
MODEL_COSTS: dict[str, tuple[float, float, float, float]] = {
    "claude-fable": (10.00, 50.00, 12.50, 1.00),
    "claude-opus": (5.00, 25.00, 6.25, 0.50),
    "claude-sonnet": (3.00, 15.00, 3.75, 0.30),
    "claude-haiku": (1.00, 5.00, 1.25, 0.10),
}

# Token counts for one model: keys ``input``, ``output``, ``cache_write``
# (5-minute TTL writes), ``cache_read``, plus optional ``cache_write_1h`` (1-hour
# TTL writes, priced higher). The keys never overlap, so summing the values
# gives the total.
TokenCounts = dict[str, int]


@dataclass(frozen=True)
class ModelPrice:
    """List prices for one model, in USD per 1M tokens.

    Attributes:
        input: Uncached input tokens.
        output: Output tokens.
        cache_write: Cache writes with the 5-minute TTL (1.25x input).
        cache_read: Cache reads.
        cache_write_1h: Cache writes with the 1-hour TTL (2x input).
    """

    input: float
    output: float
    cache_write: float
    cache_read: float
    cache_write_1h: float


def _price(inp: float, out: float, cache_read: float | None = None) -> ModelPrice:
    """Build a price with the standard cache multipliers unless a read rate is given."""
    read = round(inp * 0.1, 4) if cache_read is None else cache_read
    return ModelPrice(inp, out, inp * 1.25, read, inp * 2)


# Per model-id prefix; the longest matching prefix wins. Rates from the
# claude-api reference (cached 2026-10-06); Sonnet 5.5's cache read from the
# pricing page (2026-10-21).
MODEL_PRICES: dict[str, ModelPrice] = {
    "claude-fable-5-1": _price(10.00, 50.00, 0.25),
    "claude-fable-5": _price(10.00, 50.00),
    "claude-opus-5-5": _price(4.00, 20.00, 0.20),
    "claude-opus-5": _price(5.00, 25.00),
    "claude-opus-4-8": _price(5.00, 25.00),
    "claude-opus-4-7": _price(5.00, 25.00),
    "claude-opus-4-6": _price(5.00, 25.00),
    "claude-opus-4-5": _price(5.00, 25.00),
    "claude-opus-4": _price(15.00, 75.00),
    "claude-sonnet-5-5": _price(2.00, 10.00, 0.10),
    "claude-sonnet-5": _price(2.00, 10.00),
    "claude-sonnet-4": _price(3.00, 15.00),
    "claude-haiku-5-5": _price(0.10, 0.50),
    "claude-haiku-4-5": _price(1.00, 5.00),
    "claude-3-5-haiku": _price(0.80, 4.00),
}


def model_family(model_id: str) -> str:
    """Collapse a raw model id to its pricing-family key.

    Different versions (e.g. ``claude-opus-4-7`` and ``claude-opus-4-8``) map to
    the same family so they aggregate as one model.

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


def prices_from_litellm(data: dict[str, object]) -> dict[str, ModelPrice]:
    """Parse LiteLLM's ``model_prices_and_context_window.json`` into a price table.

    Keeps entries whose ``litellm_provider`` is ``anthropic`` and whose key starts
    with ``claude-``; per-token costs become per-1M rates. An entry missing its
    input or output cost is skipped; missing cache rates take the standard
    multipliers.

    Args:
        data: The decoded LiteLLM price file.

    Returns:
        Model id to :class:`ModelPrice`, usable as the ``prices`` overlay of
        :func:`price_for` and :func:`estimated_cost`.
    """
    out: dict[str, ModelPrice] = {}
    for key, entry in data.items():
        if not (key.startswith("claude-") and isinstance(entry, dict)):
            continue
        if entry.get("litellm_provider") != "anthropic":
            continue

        def rate(field: str, e: dict[str, object] = entry) -> float | None:
            v = e.get(field)
            ok = isinstance(v, (int, float)) and not isinstance(v, bool)
            return round(float(v) * 1e6, 6) if ok else None  # type: ignore[arg-type]

        inp = rate("input_cost_per_token")
        output = rate("output_cost_per_token")
        if inp is None or output is None:
            continue
        write = rate("cache_creation_input_token_cost")
        read = rate("cache_read_input_token_cost")
        write_1h = rate("cache_creation_input_token_cost_above_1hr")
        out[key] = ModelPrice(
            inp,
            output,
            inp * 1.25 if write is None else write,
            round(inp * 0.1, 4) if read is None else read,
            inp * 2 if write_1h is None else write_1h,
        )
    return out


def price_for(
    model_id: str, prices: dict[str, ModelPrice] | None = None
) -> ModelPrice | None:
    """Return a model's prices: longest id prefix, then family fallback.

    Args:
        model_id: The raw model identifier from a transcript.
        prices: Optional overlay (e.g. from :func:`prices_from_litellm`) merged
            over :data:`MODEL_PRICES`, so a fetched exact id beats a built-in
            prefix.

    Returns:
        The model's :class:`ModelPrice`, or ``None`` when the model is unpriced.
    """
    table = {**MODEL_PRICES, **prices} if prices else MODEL_PRICES
    m = (model_id or "").lower()
    matches = [p for p in table if m.startswith(p)]
    if matches:
        return table[max(matches, key=len)]
    family = MODEL_COSTS.get(model_family(model_id))
    if family is None:
        return None
    return ModelPrice(*family, family[0] * 2)


def model_costs(model_id: str) -> tuple[float, float, float, float] | None:
    """Return ``(input, output, cache_write, cache_read)`` per 1M tokens, or ``None``."""
    p = price_for(model_id)
    return None if p is None else (p.input, p.output, p.cache_write, p.cache_read)


def estimated_cost(
    per_model: dict[str, TokenCounts], prices: dict[str, ModelPrice] | None = None
) -> float:
    """Estimate USD cost from per-model token counts and the pricing tables.

    This is an estimate (tokens x list price), not the amount Anthropic billed.
    Models without a price add $0; callers report them as unpriced.

    Args:
        per_model: Mapping of model id to its :data:`TokenCounts`.
        prices: Optional price overlay, as in :func:`price_for`.

    Returns:
        The estimated cost in USD.
    """
    cost = 0.0
    for model_id, tok in per_model.items():
        p = price_for(model_id, prices)
        if p is None:
            continue
        cost += tok["input"] * p.input
        cost += tok["output"] * p.output
        cost += tok["cache_write"] * p.cache_write
        cost += tok.get("cache_write_1h", 0) * p.cache_write_1h
        cost += tok["cache_read"] * p.cache_read
    return cost / 1_000_000
