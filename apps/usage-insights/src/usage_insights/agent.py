"""The chat agent behind ``POST /api/agent``: a Claude loop that streams AG-UI events.

A sync port of the ceh-ag-ui agent-server template. The canvas sends its layout
edits as frontend tools; the model calls them and the run ends, because the
canvas applies the edit and starts the next run with the result. The server
runs two read-only backend tools itself: ``list_values`` and ``run_query``.

Claude keeps its own transcript per thread (thinking blocks included) and only
new AG-UI messages are folded in, so the history stays append-only. The browser
never writes the prompt: client system, developer, and assistant messages are
ignored, and only the tools in :data:`FRONTEND_TOOLS` are passed through.
"""

from __future__ import annotations

import json
import os
import threading
import uuid
from collections import OrderedDict
from collections.abc import Callable, Generator, Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import anthropic
from ag_ui.core import (
    BaseEvent,
    RunAgentInput,
    RunErrorEvent,
    RunFinishedEvent,
    RunStartedEvent,
    TextMessageContentEvent,
    TextMessageEndEvent,
    TextMessageStartEvent,
    ToolCallArgsEvent,
    ToolCallEndEvent,
    ToolCallResultEvent,
    ToolCallStartEvent,
)

from usage_insights import query, reference, store
from usage_insights.aggregate import project_labels

KEY_VAR = "C4_USAGE_INSIGHTS_API_KEY"
MODEL_VAR = "C4_USAGE_INSIGHTS_MODEL"
DEFAULT_MODEL = "claude-sonnet-5-5"
MAX_BACKEND_ROUNDS = 8  # model requests per run
MAX_THREADS = 20
MAX_STATE_SECTIONS = 50
MAX_STATE_PANELS = 200
FRONTEND_TOOLS = ("add_panel", "add_section", "move_panel", "remove_panel")
DIMENSIONS = ("project", "model", "skill", "agent", "tool")
QUERY_RANGE = "30d"  # run_query without a range

_QUERY_HELP = "; ".join(f"{m}: {', '.join(g)}" for m, g in query.GROUPINGS.items())
SYSTEM = f"""\
You help one person analyse their own Claude Code usage on a local dashboard. \
You answer by placing panels on the dashboard with add_panel, and you can add \
sections, move panels, and remove panels.

How panels work:
- The app fixes how panels look. Never try to style them.
- A panel holds a query, and the server computes what it shows. You never \
write a figure into a panel. A caption says what question the panel answers and \
never quotes a figure.
- Before placing a panel, call run_query with its query to check it returns \
rows. Use list_values to find the real project, model, skill, agent, and tool \
names before filtering on them.
- A panel query without a range follows the dashboard's range selector. \
run_query without a range uses the last 30 days.
- Each user turn starts with the current layout: section ids, and each panel's \
id and title. Add a panel to the section it fits, or add a section first: \
add_section returns the new section's id.

Queries: metric, group_by, filters (project labels, model id prefixes, or \
skill/agent/tool names), range (7d, 30d, 90d, month, all), compare \
("previous": the same metric over the previous period, not with all or with \
day or week groupings), limit (1 to 100). Allowed groupings per metric: \
{_QUERY_HELP}.

In chat, keep text to a sentence or two. Every figure you mention must come \
from a run_query result in this conversation."""

BACKEND_SCHEMAS: dict[str, tuple[str, dict[str, Any]]] = {
    "list_values": (
        "Names seen in the usage store for one dimension, so filters use real values.",
        {
            "type": "object",
            "properties": {"dimension": {"type": "string", "enum": list(DIMENSIONS)}},
            "required": ["dimension"],
        },
    ),
    "run_query": (
        (
            "Run a query read-only and get its rows, unit, and total. Check a query with "
            "this before placing it, and take every figure you mention from its result."
        ),
        {
            "type": "object",
            "properties": {"query": {"type": "object", "description": "A query spec."}},
            "required": ["query"],
        },
    ),
}


class Busy(Exception):
    """Another run holds this chat's thread."""


@dataclass
class Thread:
    """One chat's model-side state."""

    transcript: list[Any] = field(default_factory=list)  # Claude's view, thinking included
    seen: set[str] = field(default_factory=set)  # AG-UI message ids already folded in
    awaiting: set[str] = field(default_factory=set)  # tool_use ids with no result yet
    held: list[dict[str, Any]] = field(default_factory=list)  # results sent with those
    last_state: str | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)


# less-code: in-memory threads; persist if chats must survive a restart
_THREADS: OrderedDict[str, Thread] = OrderedDict()
_THREADS_LOCK = threading.Lock()


@contextmanager
def checkout(thread_id: str) -> Iterator[Thread]:
    """Hold a thread for one run; the oldest of :data:`MAX_THREADS` is dropped.

    Raises:
        Busy: A run on this thread is already going.
    """
    with _THREADS_LOCK:
        thread = _THREADS.setdefault(thread_id, Thread())
        _THREADS.move_to_end(thread_id)
        while len(_THREADS) > MAX_THREADS:
            _THREADS.popitem(last=False)
    if not thread.lock.acquire(blocking=False):
        raise Busy
    try:
        yield thread
    finally:
        thread.lock.release()


def api_key() -> str | None:
    """The chat's API key. Not ``ANTHROPIC_API_KEY``: Claude Code reads that one too."""
    return os.environ.get(KEY_VAR) or None


def make_client(key: str) -> Any:
    return anthropic.Anthropic(api_key=key)


@dataclass(frozen=True)
class Context:
    """What the backend tools read."""

    db: Path
    skill_names: Callable[[], frozenset[str]]


def _text_of(content: Any) -> str:
    if isinstance(content, str):
        return content
    return "".join(getattr(part, "text", "") for part in content or [])


def _layout_state(state: Any) -> str | None:
    """The layout summary as compact JSON, or ``None`` when it is missing or invalid."""
    if not isinstance(state, dict) or not isinstance(state.get("sections"), list):
        return None
    sections = state["sections"]
    if len(sections) > MAX_STATE_SECTIONS:
        return None
    clean: list[dict[str, Any]] = []
    panels = 0
    for s in sections:
        if not (isinstance(s, dict) and isinstance(s.get("id"), str)
                and isinstance(s.get("question"), str) and isinstance(s.get("panels"), list)):
            return None
        rows = []
        for p in s["panels"]:
            if not (isinstance(p, dict) and isinstance(p.get("id"), str)
                    and isinstance(p.get("title"), str)):
                return None
            rows.append({"id": p["id"], "title": p["title"]})
        panels += len(rows)
        clean.append({"id": s["id"], "question": s["question"], "panels": rows})
    if panels > MAX_STATE_PANELS:
        return None
    return json.dumps({"sections": clean}, separators=(",", ":"))


def fold_in(thread: Thread, run: RunAgentInput) -> None:
    """Append the canvas's tool results, the layout, and new user text as one user turn."""
    results: dict[str, dict[str, Any]] = {}
    texts: list[str] = []
    for message in run.messages:
        if message.id in thread.seen:
            continue
        thread.seen.add(message.id)
        if message.role == "tool" and message.tool_call_id in thread.awaiting:
            text = _text_of(message.content)
            results[message.tool_call_id] = {
                "type": "tool_result", "tool_use_id": message.tool_call_id,
                "content": text, "is_error": text.startswith("error"),
            }
        elif message.role == "user":
            texts.append(_text_of(message.content))
        # Assistant messages are this server's own output; client system and
        # developer messages are ignored so the browser cannot write the prompt.
    for call_id in sorted(thread.awaiting - results.keys()):
        results[call_id] = {
            "type": "tool_result", "tool_use_id": call_id, "is_error": True,
            "content": "The user stopped the run before this was applied.",
        }
    blocks: list[dict[str, Any]] = thread.held + list(results.values())
    layout = _layout_state(run.state)
    if layout is not None and layout != thread.last_state and (blocks or texts):
        # Tool results must lead a user turn, so the layout follows them.
        blocks.append({"type": "text", "text": f"Current layout: {layout}"})
        thread.last_state = layout
    blocks += [{"type": "text", "text": t} for t in texts if t]
    thread.awaiting, thread.held = set(), []
    if blocks:
        thread.transcript.append({"role": "user", "content": blocks})


def _echoable(content: list[Any]) -> list[Any]:
    """After a mid-output fallback, only text from before the last fallback block is echoed."""
    cut = max((i for i, b in enumerate(content) if b.type == "fallback"), default=None)
    if cut is None:
        return content
    return [b for b in content[:cut] if b.type == "text"] + content[cut:]


def list_values(ctx: Context, args: Any) -> str:
    dimension = args.get("dimension") if isinstance(args, dict) else None
    if dimension not in DIMENSIONS:
        raise ValueError(f"dimension must be one of {', '.join(DIMENSIONS)}")
    if not ctx.db.is_file():
        return "[]"
    with store.connect_read_only(ctx.db) as conn:
        if dimension == "project":
            sessions = {r[0]: r[1:] for r in conn.execute(
                "SELECT id, project, title, cwd, started, ended FROM sessions")}
            names = set(project_labels(sessions).values())
        elif dimension == "model":
            names = {m for (m,) in conn.execute("SELECT DISTINCT model FROM messages")
                     if m and m != "unknown"}
        elif dimension == "skill":
            skills = ctx.skill_names()
            names = {n for k, n in conn.execute(
                "SELECT DISTINCT kind, name FROM events WHERE kind IN ('skill', 'command')")
                if k == "skill" or n in skills}
        else:
            names = {n for (n,) in conn.execute(
                "SELECT DISTINCT name FROM events WHERE kind = ?", (dimension,))}
    return json.dumps(sorted(names))


def run_query(ctx: Context, args: Any) -> str:
    raw = args.get("query") if isinstance(args, dict) else None
    spec = query.parse(raw, QUERY_RANGE)
    result = query.run(
        ctx.db, spec, datetime.now().astimezone(), None,
        reference.load(ctx.db.parent).prices,
        ctx.skill_names() if spec.metric == "skill_uses" else frozenset(),
    )
    return json.dumps(result, separators=(",", ":"))


BACKEND_TOOLS: dict[str, Callable[[Context, Any], str]] = {
    "list_values": list_values,
    "run_query": run_query,
}


def _too_long(exc: Exception) -> bool:
    msg = str(exc).lower()
    return isinstance(exc, anthropic.BadRequestError) and (
        "too long" in msg or "context" in msg
    )


def _claude(
    thread: Thread, run: RunAgentInput, ctx: Context, client: Any, model: str
) -> Iterator[BaseEvent]:
    """Stream model output as AG-UI events; end on a frontend call or a final answer."""
    frontend = [t for t in run.tools or [] if t.name in FRONTEND_TOOLS]
    frontend.sort(key=lambda t: FRONTEND_TOOLS.index(t.name))  # stable, for the cache
    names = {t.name for t in frontend}
    tools = [
        {"name": t.name, "description": t.description, "eager_input_streaming": True,
         "input_schema": t.parameters or {"type": "object"}}
        for t in frontend
    ] + [
        {"name": n, "description": d, "eager_input_streaming": True, "input_schema": s}
        for n, (d, s) in BACKEND_SCHEMAS.items()
    ]
    for _round in range(MAX_BACKEND_ROUNDS):
        with client.beta.messages.stream(
            model=model,
            max_tokens=64000,
            system=SYSTEM,
            tools=tools,
            messages=thread.transcript,
            output_config={"effort": "medium"},
            cache_control={"type": "ephemeral"},
            fallbacks="default",
            betas=["server-side-fallback-2026-07-01"],
        ) as stream:
            open_blocks: dict[int, tuple[str, str]] = {}  # index -> (kind, AG-UI id)
            for event in stream:
                if event.type == "content_block_start":
                    block = event.content_block
                    if block.type == "text":
                        open_blocks[event.index] = ("text", str(uuid.uuid4()))
                        yield TextMessageStartEvent(
                            message_id=open_blocks[event.index][1], role="assistant")
                    elif block.type == "tool_use":
                        open_blocks[event.index] = ("tool", block.id)
                        yield ToolCallStartEvent(tool_call_id=block.id, tool_call_name=block.name)
                elif event.type == "content_block_delta" and event.index in open_blocks:
                    block_id = open_blocks[event.index][1]
                    if event.delta.type == "text_delta":
                        yield TextMessageContentEvent(message_id=block_id, delta=event.delta.text)
                    elif event.delta.type == "input_json_delta":
                        yield ToolCallArgsEvent(
                            tool_call_id=block_id, delta=event.delta.partial_json)
                elif event.type == "content_block_stop" and event.index in open_blocks:
                    kind, block_id = open_blocks.pop(event.index)
                    if kind == "tool":
                        yield ToolCallEndEvent(tool_call_id=block_id)
                    else:
                        yield TextMessageEndEvent(message_id=block_id)
            final = stream.get_final_message()

        thread.transcript.append({"role": "assistant", "content": _echoable(final.content)})
        calls = [b for b in final.content if b.type == "tool_use"]
        # Every call needs a result before the next request; until one is held or
        # sent, the next run's fold_in answers it with an error.
        thread.awaiting = {c.id for c in calls}
        if final.stop_reason == "refusal":
            yield RunErrorEvent(message="The model declined this request.", code="refusal")
            return
        if final.stop_reason == "max_tokens" and calls:
            yield RunErrorEvent(message="A tool call was cut off by max_tokens.",
                                code="max_tokens")
            return
        if final.stop_reason == "pause_turn":
            continue
        if final.stop_reason != "tool_use":
            return

        for call in (c for c in calls if c.name not in names):
            handler = BACKEND_TOOLS.get(call.name)
            try:
                if handler is None:
                    raise ValueError(f"unknown tool {call.name}")
                result = {"type": "tool_result", "tool_use_id": call.id,
                          "content": handler(ctx, call.input)}
            except ValueError as exc:  # bad input: eager streaming skips API validation
                result = {"type": "tool_result", "tool_use_id": call.id,
                          "is_error": True, "content": f"error: {exc}"}
            thread.held.append(result)
            thread.awaiting.discard(call.id)
            yield ToolCallResultEvent(message_id=str(uuid.uuid4()), tool_call_id=call.id,
                                      content=result["content"])
        if thread.awaiting:
            return  # the canvas applies its calls; held results go with its answers
        thread.transcript.append({"role": "user", "content": thread.held})
        thread.held = []
    yield RunErrorEvent(message="Too many steps, try a narrower question", code="max_rounds")


def run(
    thread: Thread, run_input: RunAgentInput, ctx: Context, client: Any, model: str
) -> Generator[BaseEvent]:
    """One AG-UI run: ``RUN_STARTED``, the events, then exactly one ``RUN_FINISHED`` or
    ``RUN_ERROR``. Closing the iterator (the browser went away) stops the loop before
    its next model request."""
    yield RunStartedEvent(thread_id=run_input.thread_id, run_id=run_input.run_id)
    try:
        fold_in(thread, run_input)
        for event in _claude(thread, run_input, ctx, client, model):
            yield event
            if isinstance(event, RunErrorEvent):
                return
    except Exception as exc:  # noqa: BLE001 - every failure must end the run with RUN_ERROR
        if _too_long(exc):
            yield RunErrorEvent(message="This chat is too long, start a new chat",
                                code="context_length")
        else:
            yield RunErrorEvent(message=str(exc), code=type(exc).__name__)
        return
    yield RunFinishedEvent(thread_id=run_input.thread_id, run_id=run_input.run_id)


def pump(events: Generator[BaseEvent], encode: Callable[[BaseEvent], str],
         write: Callable[[bytes], None]) -> None:
    """Write each event until the run ends or the browser goes away (Stop, a closed tab).

    Closing the run on a failed write stops it before its next model request; its
    unanswered calls get error results on the next run.
    """
    try:
        for event in events:
            write(encode(event).encode())
    except (BrokenPipeError, ConnectionResetError):
        pass
    finally:
        events.close()


def model_name() -> str:
    return os.environ.get(MODEL_VAR) or DEFAULT_MODEL
