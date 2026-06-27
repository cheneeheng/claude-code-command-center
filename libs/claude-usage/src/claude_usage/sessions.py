"""Discover and parse Claude Code session transcripts into per-session usage.

Source: ``<claude_dir>/projects/**/*.jsonl`` — one JSONL file per session, written
by Claude Code itself. Token usage lives on assistant messages. The cost on each
:class:`Session` is *estimated* (token counts x the pricing table), not the amount
Anthropic billed.
"""

from __future__ import annotations

import glob
import json
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from claude_usage.pricing import TokenCounts, estimated_cost


@dataclass
class Session:
    """A single Claude Code session rolled up from its transcript.

    Attributes:
        session_id: First 8 characters of the transcript file stem.
        project: Name of the transcript's parent directory.
        models: Sorted model ids the session used (``unknown`` excluded).
        per_model: Per-model token counts (``unknown`` excluded).
        input_tokens: Total input tokens across all models.
        output_tokens: Total output tokens across all models.
        cache_write_tokens: Total cache-creation input tokens.
        cache_read_tokens: Total cache-read input tokens.
        total_tokens: Sum of the four token totals above.
        cost_usd: Estimated cost in USD (see module docstring).
        message_count: Number of assistant messages counted.
        first_ts: ISO-8601 timestamp of the earliest record, or ``None``.
        last_ts: ISO-8601 timestamp of the latest record, or ``None``.
    """

    session_id: str
    project: str
    models: list[str]
    per_model: dict[str, TokenCounts]
    input_tokens: int
    output_tokens: int
    cache_write_tokens: int
    cache_read_tokens: int
    total_tokens: int
    cost_usd: float
    message_count: int
    first_ts: str | None
    last_ts: str | None


def claude_dirs() -> list[Path]:
    """Return the Claude config dirs, honouring a pathsep-separated ``$CLAUDE_DIR``."""
    env = os.environ.get("CLAUDE_DIR", "")
    if env:
        return [Path(p) for p in env.split(os.pathsep) if p.strip()]
    return [Path.home() / ".claude"]


def transcript_files(dirs: list[Path] | None = None) -> list[str]:
    """Return every session transcript across the given (or default) Claude dirs."""
    search = dirs if dirs is not None else claude_dirs()
    files: list[str] = []
    for d in search:
        files.extend(glob.glob(str(d / "projects" / "**" / "*.jsonl"), recursive=True))
    return sorted(set(files))


# Any: transcript records are arbitrary JSON objects with no fixed schema.
def _read_records(fpath: str) -> list[dict[str, Any]]:
    """Parse one transcript file into records, skipping blank/invalid lines."""
    records: list[dict[str, Any]] = []
    try:
        with open(fpath, encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except (OSError, PermissionError):
        return []
    return records


def _parse_ts(ts_raw: object) -> datetime | None:
    """Parse an ISO-8601 timestamp string, or return ``None`` if absent/invalid."""
    if not isinstance(ts_raw, str) or not ts_raw:
        return None
    try:
        return datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _summarize(fpath: str) -> Session | None:
    """Roll one transcript file up into a :class:`Session`, or ``None`` if it
    carries no token usage."""
    records = _read_records(fpath)
    if not records:
        return None

    per_model: dict[str, TokenCounts] = {}
    first_ts: datetime | None = None
    last_ts: datetime | None = None
    message_count = 0
    seen_uuids: set[str] = set()

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
        # "<synthetic>" marks a Claude-Code placeholder/error message, not a real
        # model; fold it into "unknown" (excluded from the model breakdown).
        model = msg.get("model", "") or "unknown"
        if model == "<synthetic>":
            model = "unknown"
        usage = msg.get("usage", {})

        bucket = per_model.setdefault(
            model, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
        )
        bucket["input"] += usage.get("input_tokens", 0)
        bucket["output"] += usage.get("output_tokens", 0)
        bucket["cache_write"] += usage.get("cache_creation_input_tokens", 0)
        bucket["cache_read"] += usage.get("cache_read_input_tokens", 0)

    if not per_model:
        return None

    input_tokens = sum(t["input"] for t in per_model.values())
    output_tokens = sum(t["output"] for t in per_model.values())
    cache_write_tokens = sum(t["cache_write"] for t in per_model.values())
    cache_read_tokens = sum(t["cache_read"] for t in per_model.values())
    total_tokens = input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
    if total_tokens == 0:
        return None

    return Session(
        session_id=Path(fpath).stem[:8],
        project=Path(fpath).parent.name,
        models=sorted(m for m in per_model if m != "unknown"),
        per_model={m: t for m, t in per_model.items() if m != "unknown"},
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_write_tokens=cache_write_tokens,
        cache_read_tokens=cache_read_tokens,
        total_tokens=total_tokens,
        cost_usd=estimated_cost(per_model),
        message_count=message_count,
        first_ts=first_ts.isoformat() if first_ts else None,
        last_ts=last_ts.isoformat() if last_ts else None,
    )


def load_sessions(dirs: list[Path] | None = None) -> list[Session]:
    """Parse every transcript and return per-session summaries, newest first.

    Args:
        dirs: Claude config dirs to search. Defaults to :func:`claude_dirs`.

    Returns:
        Sessions carrying token usage, sorted by ``last_ts`` descending.
    """
    sessions = [s for s in (_summarize(f) for f in transcript_files(dirs)) if s]
    sessions.sort(key=lambda s: s.last_ts or "", reverse=True)
    return sessions
