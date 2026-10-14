"""Discover and parse Claude Code session transcripts into per-session usage.

Source: ``<claude_dir>/projects/**/*.jsonl`` — one JSONL file per session, written
by Claude Code itself. Token usage lives on assistant messages. The cost on each
:class:`Session` is *estimated* (token counts x the pricing table), not the amount
Anthropic billed.

Parsing is split in two. :func:`parse_file` reads one transcript into keyed
records. :func:`load_usage` merges every file's records, deduplicating each
streamed reply and each tool call once across all files (resumed and forked
sessions copy earlier replies), then rolls them up into per-session summaries and
an :class:`Activity` rollup (daily / hour-of-week / tool buckets in local time).
:func:`load_sessions` is the sessions-only view of the same pass.

Subagent and workflow transcripts (any ``.jsonl`` under
``projects/<project>/<session-uuid>/``) fold into their parent session.
"""

from __future__ import annotations

import glob
import json
import os
from collections import defaultdict
from dataclasses import dataclass, field, replace
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
        tools: ``tool_use`` block counts keyed by tool name (all-time).
        daily_tools: ``tool_use`` block counts keyed by local day
            (``YYYY-MM-DD``) then tool name, holding only days with tool usage.
            Lets a consumer scope tool counts to a time window; blocks on a
            message with no parseable timestamp appear in :attr:`tools` only.
    """

    daily: list[DayBucket]
    hour_dow: list[list[int]]
    tools: dict[str, int]
    daily_tools: dict[str, dict[str, int]]


@dataclass(frozen=True)
class MessageUsage:
    """Token usage of one assistant reply, after dedup.

    Attributes:
        key: Dedup key: ``message.id`` + ``requestId``, else the record ``uuid``.
        session_id: The session that first recorded the reply.
        model: Model id (``unknown`` for synthetic or missing).
        ts: Aware UTC timestamp of the line that carried the final usage.
        input: Uncached input tokens.
        output: Output tokens.
        cache_write: Cache-write tokens with the 5-minute TTL.
        cache_read: Cache-read tokens.
        cache_write_1h: Cache-write tokens with the 1-hour TTL.
    """

    key: str
    session_id: str
    model: str
    ts: datetime | None
    input: int
    output: int
    cache_write: int
    cache_read: int
    cache_write_1h: int

    def counts(self) -> TokenCounts:
        """Return this reply's :data:`TokenCounts`."""
        return {
            "input": self.input,
            "output": self.output,
            "cache_write": self.cache_write,
            "cache_read": self.cache_read,
            "cache_write_1h": self.cache_write_1h,
        }


@dataclass(frozen=True)
class UsageEvent:
    """One countable use, e.g. a tool call.

    Attributes:
        kind: ``tool``.
        name: What was used, e.g. the tool name.
        ts: Aware UTC timestamp, or ``None``.
        session_id: The session that first recorded it.
        key: ``<kind>:<id>``, unique per event across all files.
    """

    kind: str
    name: str
    ts: datetime | None
    session_id: str
    key: str


@dataclass
class FileParse:
    """One transcript file, parsed but not yet merged.

    Attributes:
        path: The transcript path.
        session_id: The session it belongs to (parent session for subagents).
        project: The project folder name.
        first_ts: Earliest record timestamp (aware UTC), or ``None``.
        last_ts: Latest record timestamp (aware UTC), or ``None``.
        messages: Assistant replies, deduped within the file (last line wins).
        events: Uses, deduped within the file (first seen wins).
    """

    path: str
    session_id: str
    project: str
    first_ts: datetime | None
    last_ts: datetime | None
    messages: list[MessageUsage]
    events: list[UsageEvent]


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


def _utc(ts_raw: object) -> datetime | None:
    """Parse a timestamp into an aware UTC datetime.

    Naive timestamps (no offset) are treated as UTC, mirroring how Claude Code
    writes them.
    """
    dt = _parse_ts(ts_raw)
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _locate(fpath: str) -> tuple[str, str]:
    """Return ``(project, session_id)`` for a transcript path.

    ``projects/<project>/<stem>.jsonl`` is a parent transcript, session ``stem``.
    Anything deeper, ``projects/<project>/<session-uuid>/.../*.jsonl``, is a
    subagent or workflow transcript folded into ``<session-uuid>``.
    """
    p = Path(fpath)
    parts = p.parts[:-1]
    anchors = [i for i, part in enumerate(parts) if part == "projects"]
    if not anchors:
        return p.parent.name, p.stem[:8]
    rel = parts[anchors[-1] + 1 :]
    if len(rel) <= 1:
        return p.parent.name, p.stem[:8]
    return rel[0], rel[1][:8]


def _message_key(rec: dict[str, Any], msg: dict[str, Any]) -> str | None:
    """Dedup key of an assistant line: ``message.id`` + ``requestId``, else ``uuid``."""
    mid = msg.get("id")
    if isinstance(mid, str) and mid:
        return f"{mid}:{rec.get('requestId') or ''}"
    uid = rec.get("uuid")
    return uid if isinstance(uid, str) and uid else None


def _int(value: object) -> int:
    """Coerce a usage field to an int, treating anything non-numeric as 0."""
    return value if isinstance(value, int) else 0


def parse_file(fpath: str) -> FileParse:
    """Parse one transcript file into keyed replies and uses.

    A streamed reply spans several lines that share ``message.id`` and
    ``requestId``. The last line wins for usage, because it carries the final
    counts, and ``tool_use`` blocks are collected from every line, deduped by
    block ``id``. Blocks without an ``id`` are never deduped.

    Args:
        fpath: Path of a ``.jsonl`` transcript.

    Returns:
        The file's :class:`FileParse`. Unreadable files give an empty parse.
    """
    project, session_id = _locate(fpath)
    messages: dict[str, MessageUsage] = {}
    events: dict[str, UsageEvent] = {}
    first_ts: datetime | None = None
    last_ts: datetime | None = None

    for i, rec in enumerate(_read_records(fpath)):
        ts = _utc(rec.get("timestamp"))
        if ts is not None:
            first_ts = ts if first_ts is None else min(first_ts, ts)
            last_ts = ts if last_ts is None else max(last_ts, ts)

        # Token usage only lives on assistant messages.
        if rec.get("type") != "assistant":
            continue
        msg = rec.get("message")
        if not isinstance(msg, dict):
            msg = {}
        key = _message_key(rec, msg) or f"{fpath}#{i}"
        usage = msg.get("usage")
        if not isinstance(usage, dict):
            usage = {}
        cache = usage.get("cache_creation")
        write_1h = _int(cache.get("ephemeral_1h_input_tokens")) if isinstance(cache, dict) else 0
        messages[key] = MessageUsage(
            key=key,
            session_id=session_id,
            model=_normalize_model(msg),
            ts=ts,
            input=_int(usage.get("input_tokens")),
            output=_int(usage.get("output_tokens")),
            cache_write=max(0, _int(usage.get("cache_creation_input_tokens")) - write_1h),
            cache_read=_int(usage.get("cache_read_input_tokens")),
            cache_write_1h=write_1h,
        )

        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for j, block in enumerate(content):
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            name = block.get("name")
            if not isinstance(name, str) or not name:
                continue
            bid = block.get("id")
            ekey = f"tool:{bid}" if isinstance(bid, str) and bid else f"tool:{fpath}#{i}.{j}"
            events.setdefault(ekey, UsageEvent("tool", name, ts, session_id, ekey))

    return FileParse(
        path=fpath,
        session_id=session_id,
        project=project,
        first_ts=first_ts,
        last_ts=last_ts,
        messages=list(messages.values()),
        events=list(events.values()),
    )


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
    daily_tools: dict[str, dict[str, int]] = field(
        default_factory=lambda: defaultdict(lambda: defaultdict(int))
    )

    def add_message(
        self,
        dt: datetime,
        session_id: str,
        model: str,
        counts: TokenCounts,
    ) -> None:
        """Attribute one assistant message's usage to its local day/hour buckets."""
        total = sum(counts.values())
        if total <= 0:
            return
        day = dt.date().isoformat()
        self.daily_tokens[day] += total
        self.daily_cost[day] += estimated_cost({model: counts})
        self.daily_sessions[day].add(session_id)
        if model != "unknown":
            self.daily_family[day][model_family(model)] += total
        self.hour_dow[dt.weekday()][dt.hour] += total

    def add_tool(self, name: str, day: str | None = None) -> None:
        """Count one ``tool_use`` block by name.

        Also attributes it to ``day`` (local ``YYYY-MM-DD``) when known, so tool
        counts can be scoped to a time window."""
        self.tools[name] += 1
        if day is not None:
            self.daily_tools[day][name] += 1

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
        daily_tools = {d: dict(t) for d, t in self.daily_tools.items()}
        return Activity(
            daily=daily,
            hour_dow=self.hour_dow,
            tools=dict(self.tools),
            daily_tools=daily_tools,
        )


def _session(
    session_id: str,
    project: str,
    span: tuple[datetime | None, datetime | None],
    messages: list[MessageUsage],
) -> Session | None:
    """Roll one session's deduped replies into a :class:`Session`, or ``None`` if
    they carry no token usage."""
    if not messages:
        return None
    per_model: dict[str, TokenCounts] = {}
    for m in messages:
        bucket = per_model.setdefault(m.model, dict.fromkeys(m.counts(), 0))
        for k, v in m.counts().items():
            bucket[k] += v
    tokens = {k: sum(t[k] for t in per_model.values()) for k in messages[0].counts()}
    total_tokens = sum(tokens.values())
    if total_tokens == 0:
        return None
    first_ts, last_ts = span
    return Session(
        session_id=session_id,
        project=project,
        models=sorted(m for m in per_model if m != "unknown"),
        per_model={m: t for m, t in per_model.items() if m != "unknown"},
        input_tokens=tokens["input"],
        output_tokens=tokens["output"],
        cache_write_tokens=tokens["cache_write"] + tokens["cache_write_1h"],
        cache_read_tokens=tokens["cache_read"],
        total_tokens=total_tokens,
        cost_usd=estimated_cost(per_model),
        message_count=len(messages),
        first_ts=first_ts.isoformat() if first_ts else None,
        last_ts=last_ts.isoformat() if last_ts else None,
    )


def _merge(parses: list[FileParse]) -> tuple[list[Session], Activity]:
    """Merge parsed files into sessions and an activity rollup.

    Dedup is global across ``parses``: a reply seen in several files counts once,
    with the usage of the last line seen and the session that saw it first. Each
    tool call likewise counts once.

    Args:
        parses: The :class:`FileParse` of every transcript to include.

    Returns:
        A ``(sessions, activity)`` tuple, sessions sorted by ``last_ts``
        descending.
    """
    messages: dict[str, MessageUsage] = {}
    events: dict[str, UsageEvent] = {}
    projects: dict[str, str] = {}
    spans: dict[str, tuple[datetime | None, datetime | None]] = {}
    for fp in parses:
        projects.setdefault(fp.session_id, fp.project)
        lo, hi = spans.get(fp.session_id, (None, None))
        if fp.first_ts is not None:
            lo = fp.first_ts if lo is None else min(lo, fp.first_ts)
        if fp.last_ts is not None:
            hi = fp.last_ts if hi is None else max(hi, fp.last_ts)
        spans[fp.session_id] = (lo, hi)
        for m in fp.messages:
            prev = messages.get(m.key)
            messages[m.key] = m if prev is None else replace(m, session_id=prev.session_id)
        for e in fp.events:
            events.setdefault(e.key, e)

    acc = _ActivityAccumulator()
    by_session: dict[str, list[MessageUsage]] = defaultdict(list)
    for m in messages.values():
        by_session[m.session_id].append(m)
        if m.ts is not None:
            acc.add_message(m.ts.astimezone(), m.session_id, m.model, m.counts())
    for e in events.values():
        day = e.ts.astimezone().date().isoformat() if e.ts is not None else None
        acc.add_tool(e.name, day)

    sessions = [
        s
        for sid in projects
        if (s := _session(sid, projects[sid], spans[sid], by_session.get(sid, [])))
    ]
    sessions.sort(key=lambda s: s.last_ts or "", reverse=True)
    return sessions, acc.finalize()


def load_usage(dirs: list[Path] | None = None) -> tuple[list[Session], Activity]:
    """Parse every transcript once into sessions and an activity rollup.

    Args:
        dirs: Claude config dirs to search. Defaults to :func:`claude_dirs`.

    Returns:
        A ``(sessions, activity)`` tuple. ``sessions`` carry token usage, sorted by
        ``last_ts`` descending (identical to :func:`load_sessions`).
    """
    return _merge([parse_file(f) for f in transcript_files(dirs)])


def load_sessions(dirs: list[Path] | None = None) -> list[Session]:
    """Parse every transcript and return per-session summaries, newest first.

    Args:
        dirs: Claude config dirs to search. Defaults to :func:`claude_dirs`.

    Returns:
        Sessions carrying token usage, sorted by ``last_ts`` descending.
    """
    return load_usage(dirs)[0]
