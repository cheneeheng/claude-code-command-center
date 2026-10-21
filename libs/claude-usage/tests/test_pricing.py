"""Unit tests for the public pricing API (model_family, model_costs, estimated_cost)."""

from __future__ import annotations

from claude_usage import (
    MODEL_COSTS,
    ModelPrice,
    estimated_cost,
    model_costs,
    model_family,
    price_for,
    prices_from_litellm,
)


def test_model_family_matches_each_known_family() -> None:
    assert model_family("claude-opus-4-8") == "claude-opus"
    assert model_family("claude-sonnet-5") == "claude-sonnet"
    assert model_family("claude-haiku-4-5-20251001") == "claude-haiku"
    assert model_family("claude-fable-5") == "claude-fable"


def test_model_family_is_case_insensitive() -> None:
    assert model_family("CLAUDE-OPUS-4-8") == "claude-opus"


def test_model_family_unknown_returns_input_unchanged() -> None:
    assert model_family("gpt-4o") == "gpt-4o"
    assert model_family("") == ""


def test_model_costs_known_and_unknown() -> None:
    assert model_costs("claude-opus-4-8") == MODEL_COSTS["claude-opus"]
    assert model_costs("gpt-4o") is None


def test_estimated_cost_sums_all_four_token_buckets() -> None:
    # 1M of each bucket for opus -> input+output+cache_write+cache_read list prices.
    tok = {"input": 1_000_000, "output": 1_000_000, "cache_write": 1_000_000, "cache_read": 1_000_000}
    expected = sum(MODEL_COSTS["claude-opus"])
    assert estimated_cost({"claude-opus-4-8": tok}) == expected


def test_estimated_cost_skips_unknown_models() -> None:
    tok = {"input": 1_000_000, "output": 0, "cache_write": 0, "cache_read": 0}
    assert estimated_cost({"mystery-model": tok}) == 0.0


def test_estimated_cost_empty_is_zero() -> None:
    assert estimated_cost({}) == 0.0


def test_sonnet_5_5_cache_read_is_0_05x_input() -> None:
    # Pricing page (fetched 2026-10-21): Sonnet 5.5 cache hits are $0.10 / MTok.
    p = price_for("claude-sonnet-5-5")
    assert p is not None and p.cache_read == 0.10


def test_prices_from_litellm_maps_anthropic_entries() -> None:
    data = {
        "claude-sonnet-5-5": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 2e-06,
            "output_cost_per_token": 1e-05,
            "cache_creation_input_token_cost": 2.5e-06,
            "cache_read_input_token_cost": 1e-07,
            "cache_creation_input_token_cost_above_1hr": 4e-06,
            "max_tokens": 128000,
        },
        "claude-haiku-5-5": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 1e-07,
            "output_cost_per_token": 5e-07,
        },
        "bedrock/claude-sonnet-5-5": {
            "litellm_provider": "bedrock",
            "input_cost_per_token": 9e-06,
            "output_cost_per_token": 9e-06,
        },
        "claude-sonnet-5-5@20261001": {
            "litellm_provider": "vertex_ai-anthropic_models",
            "input_cost_per_token": 9e-06,
            "output_cost_per_token": 9e-06,
        },
        "claude-no-output": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 1e-06,
        },
        "sample_spec": {"litellm_provider": "anthropic"},
    }
    prices = prices_from_litellm(data)
    assert set(prices) == {"claude-sonnet-5-5", "claude-haiku-5-5"}
    s = prices["claude-sonnet-5-5"]
    assert (s.input, s.output, s.cache_write, s.cache_read, s.cache_write_1h) == (
        2.0,
        10.0,
        2.5,
        0.1,
        4.0,
    )
    h = prices["claude-haiku-5-5"]
    # Missing cache rates fall back to the standard multipliers (1h: 2x input).
    assert h.cache_write_1h == 0.2


def test_overlay_exact_id_beats_builtin_prefix() -> None:
    overlay = {"claude-opus-4-8-20260101": ModelPrice(1.0, 2.0, 3.0, 4.0, 5.0)}
    assert price_for("claude-opus-4-8-20260101", overlay) == overlay[
        "claude-opus-4-8-20260101"
    ]
    # Ids the overlay lacks still price from the built-in table.
    assert price_for("claude-3-5-haiku-x", overlay) == price_for("claude-3-5-haiku-x")
    tok = {"input": 1_000_000, "output": 0, "cache_write": 0, "cache_read": 0}
    assert estimated_cost({"claude-opus-4-8-20260101": tok}, overlay) == 1.0


def test_no_overlay_is_unchanged() -> None:
    tok = {"input": 1_000_000, "output": 1_000_000, "cache_write": 0, "cache_read": 0}
    per_model = {"claude-opus-4-8": tok}
    assert estimated_cost(per_model) == estimated_cost(per_model, None)
    assert estimated_cost(per_model, {}) == estimated_cost(per_model)
    assert price_for("claude-opus-4-8", {}) == price_for("claude-opus-4-8")
