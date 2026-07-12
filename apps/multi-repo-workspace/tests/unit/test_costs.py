"""costs: result-event usage extraction + cost policy (estimate canonical)."""

from __future__ import annotations

from roundtable.costs import extract

SNAKE = {
    "input_tokens": 1000,
    "output_tokens": 500,
    "cache_creation_input_tokens": 100,
    "cache_read_input_tokens": 50,
}
CAMEL = {
    "inputTokens": 1000,
    "outputTokens": 500,
    "cacheCreationInputTokens": 100,
    "cacheReadInputTokens": 50,
}
COUNTS = {"input": 1000, "output": 500, "cache_write": 100, "cache_read": 50}


def test_model_usage_preferred_over_usage():
    ev = {
        "type": "result",
        "modelUsage": {"claude-sonnet-4-5": CAMEL},
        "usage": {"input_tokens": 9},
        "total_cost_usd": 0.07,
    }
    out = extract(ev, "claude-opus-4-8")
    assert out["usage"] == {"claude-sonnet-4-5": COUNTS}
    assert out["cost_est_usd"] > 0
    assert out["cost_reported_usd"] == 0.07


def test_usage_fallback_uses_fallback_model():
    out = extract({"usage": SNAKE}, "claude-sonnet-4-5")
    assert out["usage"] == {"claude-sonnet-4-5": COUNTS}
    assert out["cost_est_usd"] > 0


def test_unknown_model_yields_null_estimate_never_zero():
    out = extract({"modelUsage": {"mystery-model": SNAKE}}, None)
    assert out["cost_est_usd"] is None
    assert out["usage"] == {"mystery-model": COUNTS}


def test_no_usage_no_fallback():
    out = extract({"total_cost_usd": "not a number"}, None)
    assert out == {"usage": None, "cost_est_usd": None, "cost_reported_usd": None}


def test_usage_without_fallback_model_ignored():
    out = extract({"usage": SNAKE}, None)
    assert out["usage"] is None
    assert out["cost_est_usd"] is None


def test_non_dict_model_usage_blocks_skipped():
    out = extract({"modelUsage": {"claude-sonnet-4-5": "bad"}}, None)
    assert out["usage"] is None


def test_missing_keys_default_zero_and_non_numeric_ignored():
    out = extract({"modelUsage": {"claude-haiku-4-5": {"input_tokens": "NaN"}}}, None)
    assert out["usage"] == {
        "claude-haiku-4-5": {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
    }
    assert out["cost_est_usd"] == 0.0  # known model, zero tokens: a real $0 estimate


def test_reported_cost_int_accepted():
    assert extract({"total_cost_usd": 1}, None)["cost_reported_usd"] == 1.0
