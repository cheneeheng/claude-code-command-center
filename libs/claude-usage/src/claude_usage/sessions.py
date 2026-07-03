"""Discover and parse Claude Code session transcripts into per-session usage.

Source: ``<claude_dir>/projects/**/*.jsonl`` — one JSONL file per session, written
by Claude Code itself. Token usage lives on assistant messages. The cost on each
:class:`Session` is *estimated* (token counts x the pricing table), not the amount
Anthropic billed.

A single :func:`load_usage` pass produces both the per-session summaries and an
:class:`Activity` rollup (per-message daily / hour-of-week / tool buckets in local
time). :func:`load_sessions` is the sessions-only view of the same pass.
"""

from __future__ import annotations

import glob
import json
import os
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from claude_usage.pricing import (
    TokenCounts,
    estimated_cost,
    model_family,
)

# Days of per-message daily history retained in :class:`Activity` (52 weeks).
ACTIVITY_DAYS = 364


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


@dataclass
class DayBucket:
    """Per-message usage attributed to one local calendar day.

    Attributes:
        date: The local-time day as an ISO ``YYYY-MM-DD`` string.
        tokens: Total tokens (all four classes) across the day's messages.
        cost: Estimated cost in USD (pricing table) for the day.
        sessions: Number of distinct sessions with a counted message that day.
        per_family: Tokens keyed by model family (``unknown`` excluded).
    """

    date: str
    tokens: int
    cost: float
    sessions: int
    per_family: dict[str, int]


@dataclass
class Activity:
    """Per-message activity rollups, bucketed in local time.

    Attributes:
        daily: The last :data:`ACTIVITY_DAYS` local days, padded with zero-days,
            oldest first.
        hour_dow: A 7x24 token matrix; rows are weekdays (Mon..Sun), columns are
            hours (0..23).
        tools: ``tool_use`` block counts keyed by tool name.
    """

    daily: list[DayBucket]
    hour_dow: list[list[int]]
    tools: dict[str, int]


def claude_dirs() -> list[Path]:
    """Return the Claude config dirs, honouring a pathsep-separated ``$C4_CLAUDE_DIR``."""
    env = os.environ.get("C4_CLAUDE_DIR", "")
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


def _local_dt(ts_raw: object) -> datetime | None:
    """Parse a timestamp and convert it to an aware local-time datetime.

    Naive timestamps (no offset) are treated as UTC before conversion, mirroring
    how Claude Code writes them.
    """
    dt = _parse_ts(ts_raw)
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone()


def _normalize_model(msg: dict[str, Any]) -> str:
    """Return the message's model id, folding ``<synthetic>``/empty into ``unknown``."""
    model = msg.get("model", "") or "unknown"
    return "unknown" if model == "<synthetic>" else model


@dataclass
class _ActivityAccumulator:
    """Mutable cross-file activity buckets, finalized into an :class:`Activity`."""

    daily_tokens: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    daily_cost: dict[str, float] = field(default_factory=lambda: defaultdict(float))
    daily_family: dict[str, dict[str, int]] = field(
        default_factory=lambda: defaultdict(lambda: defaultdict(int))
    )
    daily_sessions: dict[str, set[str]] = field(
        default_factory=lambda: defaultdict(set)
    )
    hour_dow: list[list[int]] = field(
        default_factory=lambda: [[0] * 24 for _ in range(7)]
    )
    tools: dict[str, int] = field(default_factory=lambda: defaultdict(int))

    def add_message(
        self,
        dt: datetime,
        session_id: str,
        model: str,
        counts: TokenCounts,
    ) -> None:
        """Attribute one assistant message's usage to its local day/hour buckets."""
        total = counts["input"] + counts["output"] + counts["cache_write"] + counts["cache_read"]
        if total <= 0:
            return
        day = dt.date().isoformat()
        self.daily_tokens[day] += total
        self.daily_cost[day] += estimated_cost({model: counts})
        self.daily_sessions[day].add(session_id)
        if model != "unknown":
            self.daily_family[day][model_family(model)] += total
        self.hour_dow[dt.weekday()][dt.hour] += total

    def add_tool(self, name: object) -> None:
        """Count one ``tool_use`` block by name, skipping missing/empty names."""
        if isinstance(name, str) and name:
            self.tools[name] += 1

    def finalize(self) -> Activity:
        """Pad the daily buckets to the trailing window and freeze into an Activity."""
        today = datetime.now().astimezone().date()
        span = [
            (today - timedelta(days=i)).isoformat()
            for i in range(ACTIVITY_DAYS - 1, -1, -1)
        ]
        daily = [
            DayBucket(
                date=d,
                tokens=self.daily_tokens.get(d, 0),
                cost=self.daily_cost.get(d, 0.0),
                sessions=len(self.daily_sessions.get(d, ())),
                per_family=dict(self.daily_family.get(d, {})),
            )
            for d in span
        ]
        return Activity(daily=daily, hour_dow=self.hour_dow, tools=dict(self.tools))


def _summarize(fpath: str, acc: _ActivityAccumulator) -> Session | None:
    """Roll one transcript file up into a :class:`Session`, or ``None`` if it
    carries no token usage.

    Each assistant message also feeds the shared ``acc`` activity buckets in the
    same single pass over the file's records.
    """
    records = _read_records(fpath)
    if not records:
        return None

    session_id = Path(fpath).stem[:8]
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
        model = _normalize_model(msg)
        usage = msg.get("usage", {})

        counts: TokenCounts = {
            "input": usage.get("input_tokens", 0),
            "output": usage.get("output_tokens", 0),
            "cache_write": usage.get("cache_creation_input_tokens", 0),
            "cache_read": usage.get("cache_read_input_tokens", 0),
        }

        bucket = per_model.setdefault(
            model, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}
        )
        for k, v in counts.items():
            bucket[k] += v

        local = _local_dt(rec.get("timestamp"))
        if local is not None:
            acc.add_message(local, session_id, model, counts)
        content = msg.get("content")
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    acc.add_tool(block.get("name"))

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
        session_id=session_id,
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


def load_usage(dirs: list[Path] | None = None) -> tuple[list[Session], Activity]:
    """Parse every transcript once into sessions and an activity rollup.

    A single pass over each transcript feeds both the per-session summaries and the
    per-message :class:`Activity` buckets, so transcripts are read only once.

    Args:
        dirs: Claude config dirs to search. Defaults to :func:`claude_dirs`.

    Returns:
        A ``(sessions, activity)`` tuple. ``sessions`` carry token usage, sorted by
        ``last_ts`` descending (identical to :func:`load_sessions`).
    """
    acc = _ActivityAccumulator()
    sessions = [s for s in (_summarize(f, acc) for f in transcript_files(dirs)) if s]
    sessions.sort(key=lambda s: s.last_ts or "", reverse=True)
    return sessions, acc.finalize()


def load_sessions(dirs: list[Path] | None = None) -> list[Session]:
    """Parse every transcript and return per-session summaries, newest first.

    Args:
        dirs: Claude config dirs to search. Defaults to :func:`claude_dirs`.

    Returns:
        Sessions carrying token usage, sorted by ``last_ts`` descending.
    """
    return load_usage(dirs)[0]
