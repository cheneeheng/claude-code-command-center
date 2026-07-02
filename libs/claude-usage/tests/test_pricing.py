"""Unit tests for the public pricing API (model_family, model_costs, estimated_cost)."""

from __future__ import annotations

from claude_usage import MODEL_COSTS, estimated_cost, model_costs, model_family


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
