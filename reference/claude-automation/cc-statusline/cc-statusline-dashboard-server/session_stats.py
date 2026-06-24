"""Historical usage stats from Claude Code session transcripts.

SOURCE
    ~/.claude/projects/**/*.jsonl  (one JSONL file per session, written by
    Claude Code itself). Each assistant message carries a `usage` block with
    exact token counts.

WHAT THIS MODULE PRODUCES
    Per-session token totals and a *computed* cost. The cost here is ESTIMATED:
    token counts are multiplied by the pricing table in dashboard_config. It is
    not the amount Anthropic billed. For the authoritative per-session API cost
    of *currently live* sessions, see live_statusline.py — merge.py overlays that
    actual cost on top of these estimates.

PUBLIC API
    load_sessions()           -> list of per-session dicts (newest first)
    summarize_sessions(rows)   -> aggregate stats (totals, by_day/project/model)
"""

import json
import glob
from pathlib import Path
from datetime import datetime, date, timedelta
from collections import defaultdict

import dashboard_config
from dashboard_config import model_costs


def _transcript_files() -> list[str]:
    """Every session transcript across all configured CLAUDE_DIRS."""
    files: list[str] = []
    for claude_dir in dashboard_config.CLAUDE_DIRS:
        pattern = str(claude_dir / "projects" / "**" / "*.jsonl")
        files.extend(glob.glob(pattern, recursive=True))
    return sorted(set(files))


def _read_records(fpath: str) -> list[dict]:
    """Parse one transcript file into a list of records, skipping bad lines."""
    records = []
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except (OSError, PermissionError):
        return []
    return records


def _parse_ts(ts_raw):
    """ISO-8601 string -> datetime, or None if absent/unparseable."""
    if not ts_raw:
        return None
    try:
        return datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _estimated_cost(per_model: dict) -> float:
    """Cost from token counts x the dashboard_config pricing table (an estimate)."""
    cost = 0.0
    for model_id, tok in per_model.items():
        costs = model_costs(model_id)
        if not costs:
            continue
        inp_c, out_c, cw_c, cr_c = costs
        cost += (tok["input"]       / 1_000_000) * inp_c
        cost += (tok["output"]      / 1_000_000) * out_c
        cost += (tok["cache_write"] / 1_000_000) * cw_c
        cost += (tok["cache_read"]  / 1_000_000) * cr_c
    return cost


def _summarize_session(fpath: str) -> dict | None:
    """Roll one transcript file up into a single session summary, or None if it
    carries no token usage."""
    records = _read_records(fpath)
    if not records:
        return None

    # Per-model token counts so distinct versions cost out correctly and the UI
    # can label each one (e.g. claude-opus-4-7 vs claude-opus-4-8).
    per_model: dict = {}  # model_id -> {input, output, cache_write, cache_read}
    first_ts = last_ts = None
    message_count = 0
    seen_uuids = set()  # dedup within this session only

    for rec in records:
        uid = rec.get("uuid") or rec.get("requestId")
        if uid:
            if uid in seen_uuids:
                continue
            seen_uuids.add(uid)

        ts = _parse_ts(rec.get("timestamp"))
        if ts:
            if first_ts is None or ts < first_ts:
                first_ts = ts
            if last_ts is None or ts > last_ts:
                last_ts = ts

        # Token usage only lives on assistant messages.
        if rec.get("type") != "assistant":
            continue

        message_count += 1
        msg = rec.get("message", {})
        # "<synthetic>" marks a Claude-Code-generated placeholder/error message,
        # not a real model. Rendered raw it parses as an HTML tag client-side, so
        # fold it into "unknown" (excluded from the model breakdown below).
        model = msg.get("model", "") or "unknown"
        if model == "<synthetic>":
            model = "unknown"
        usage = msg.get("usage", {})

        bucket = per_model.setdefault(
            model, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
        )
        bucket["input"]       += usage.get("input_tokens", 0)
        bucket["output"]      += usage.get("output_tokens", 0)
        bucket["cache_write"] += usage.get("cache_creation_input_tokens", 0)
        bucket["cache_read"]  += usage.get("cache_read_input_tokens", 0)

    if not per_model:
        return None

    input_tokens       = sum(t["input"]       for t in per_model.values())
    output_tokens      = sum(t["output"]      for t in per_model.values())
    cache_write_tokens = sum(t["cache_write"] for t in per_model.values())
    cache_read_tokens  = sum(t["cache_read"]  for t in per_model.values())
    total_tokens = input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
    if total_tokens == 0:
        return None

    return {
        "session_id":         Path(fpath).stem[:8],
        "project":            Path(fpath).parent.name,
        "models":             sorted(m for m in per_model if m != "unknown"),
        "per_model":          {m: t for m, t in per_model.items() if m != "unknown"},
        "input_tokens":       input_tokens,
        "output_tokens":      output_tokens,
        "cache_write_tokens": cache_write_tokens,
        "cache_read_tokens":  cache_read_tokens,
        "total_tokens":       total_tokens,
        "cost_usd":           _estimated_cost(per_model),  # estimate; see module docstring
        "message_count":      message_count,
        "first_ts":           first_ts.isoformat() if first_ts else None,
        "last_ts":            last_ts.isoformat() if last_ts else None,
    }


def load_sessions() -> list[dict]:
    """Parse every transcript and return per-session summaries, newest first."""
    sessions = [s for s in map(_summarize_session, _transcript_files()) if s]
    sessions.sort(key=lambda s: s["last_ts"] or "", reverse=True)
    return sessions


# ── Aggregation ────────────────────────────────────────────────────────────────

def _empty_stats() -> dict:
    return {
        "total_sessions":    0,
        "total_tokens":      0,
        "total_input":       0,
        "total_output":      0,
        "total_cache_write": 0,
        "total_cache_read":  0,
        "total_cost_usd":    0.0,
        "by_day":            [],
        "by_project":        [],
        "by_model":          [],
    }


def _by_day(sessions: list[dict]) -> list[dict]:
    """Tokens / cost / session count per calendar day, padded to the last 30 days."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": 0})
    for s in sessions:
        if not s["last_ts"]:
            continue
        day = s["last_ts"][:10]
        buckets[day]["tokens"]   += s["total_tokens"]
        buckets[day]["cost"]     += s["cost_usd"]
        buckets[day]["sessions"] += 1

    today = date.today()
    zero = {"tokens": 0, "cost": 0.0, "sessions": 0}
    days = [(today - timedelta(days=i)).isoformat() for i in range(29, -1, -1)]
    return [{"date": d, **buckets.get(d, zero)} for d in days]


def _by_project(sessions: list[dict]) -> list[dict]:
    """Top 10 projects by token volume."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0, "sessions": 0})
    for s in sessions:
        p = s["project"] or "unknown"
        buckets[p]["tokens"]   += s["total_tokens"]
        buckets[p]["cost"]     += s["cost_usd"]
        buckets[p]["sessions"] += 1
    ranked = sorted(buckets.items(), key=lambda kv: kv[1]["tokens"], reverse=True)[:10]
    return [{"project": p, **v} for p, v in ranked]


def _by_model(sessions: list[dict]) -> list[dict]:
    """Tokens / estimated cost per raw model id (versions kept distinct)."""
    buckets = defaultdict(lambda: {"tokens": 0, "cost": 0.0})
    for s in sessions:
        for m, tok in (s.get("per_model") or {}).items():
            buckets[m]["tokens"] += tok["input"] + tok["output"] + tok["cache_write"] + tok["cache_read"]
            buckets[m]["cost"]   += _estimated_cost({m: tok})
    ranked = sorted(
        ((m, v) for m, v in buckets.items() if m and v["tokens"] > 0),
        key=lambda kv: kv[1]["tokens"], reverse=True,
    )
    return [{"model": m, **v} for m, v in ranked]


def summarize_sessions(sessions: list[dict]) -> dict:
    """Aggregate per-session rows into the dashboard's summary stats block."""
    if not sessions:
        return _empty_stats()

    total_input       = sum(s["input_tokens"]       for s in sessions)
    total_output      = sum(s["output_tokens"]      for s in sessions)
    total_cache_write = sum(s["cache_write_tokens"] for s in sessions)
    total_cache_read  = sum(s["cache_read_tokens"]  for s in sessions)

    return {
        "total_sessions":    len(sessions),
        "total_input":       total_input,
        "total_output":      total_output,
        "total_cache_write": total_cache_write,
        "total_cache_read":  total_cache_read,
        "total_cost_usd":    sum(s["cost_usd"] for s in sessions),
        "total_tokens":      total_input + total_output + total_cache_write + total_cache_read,
        "by_day":            _by_day(sessions),
        "by_project":        _by_project(sessions),
        "by_model":          _by_model(sessions),
    }
