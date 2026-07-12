"""Planning sessions: multi-turn `claude -p` conversations with --resume.

The CLI owns conversation state: turn 1 captures `session_id` from the stream-json
init event; later turns pass `--resume <session_id>`. The app never builds a message
array. Transcripts persist app-side as sibling NDJSON (raw events + synthetic
`roundtable_*` markers); produced plans are detected by a before/after filesystem
snapshot of the planning dir — trust files, not prose.
"""

from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
import threading
from datetime import datetime, timezone
from pathlib import Path
from queue import Empty, Queue
from typing import IO, Any, Iterator

from roundtable import costs, locks, plans, registry
from roundtable.registry import Project

# Session status machine (closed set): edges validated in _transition.
ALLOWED: set[tuple[str, str]] = {
    ("streaming", "idle"),  # turn end / stop
    ("idle", "streaming"),  # message
    ("streaming", "failed"),  # spawn/parse fatal
    ("idle", "closed"),  # close
}
STATUSES = ("idle", "streaming", "closed", "failed")

_END = None  # queue sentinel


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_id(prefix: str) -> str:
    """App-generated, prefixed, URL-safe public ID (never a DB auto-increment)."""
    return f"{prefix}_{secrets.token_urlsafe(12)}"


def resolve_bin(claude_bin: str) -> str | None:
    """claude_bin resolved on PATH or as an explicit file (~/$VARS expanded)."""
    expanded = os.path.expandvars(os.path.expanduser(claude_bin))
    if shutil.which(expanded) is not None:
        return expanded
    return expanded if os.path.isfile(expanded) else None


def build_claude_cmd(project: Project, permission_mode: str) -> list[str] | None:
    """The shared `claude -p` argv (planning turns and implement runs alike);
    None when claude_bin does not resolve."""
    bin_ = resolve_bin(project.claude_bin)
    if bin_ is None:
        return None
    cmd = [
        bin_,
        "-p",
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        permission_mode,
        "--max-turns",
        str(project.max_turns),
        "--allowedTools",
        ",".join(project.allowed_tools),
    ]
    if project.model:
        cmd += ["--model", project.model]
    cmd += project.claude_extra_args  # additive escape hatch, appended last
    return cmd


def spawn_claude(cmd: list[str], cwd: str, prompt: str) -> subprocess.Popen[str]:
    """Spawn claude with PROMPT on stdin (no shell), line-buffered stdout."""
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    stdin: IO[str] = proc.stdin  # type: ignore[assignment]  # PIPE guarantees a stream
    stdin.write(prompt)
    stdin.close()
    return proc


def stop_process(proc: subprocess.Popen[str], grace: float = 5.0) -> None:
    """terminate() then kill() after GRACE seconds."""
    proc.terminate()
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        proc.kill()


def format_parsed(ev: dict[str, Any]) -> list[dict[str, str]]:
    """One stream-json event -> display items [{kind, text}]. kind: text|tool|status."""
    etype = ev.get("type")
    if etype == "assistant":
        items: list[dict[str, str]] = []
        for block in ev.get("message", {}).get("content", []):
            btype = block.get("type")
            if btype == "text":
                text = block.get("text", "").strip()
                if text:
                    items.append({"kind": "text", "text": text})
            elif btype == "tool_use":
                name = block.get("name", "tool")
                digest = _tool_digest(block.get("input", {}))
                items.append(
                    {
                        "kind": "tool",
                        "text": f"▸ {name}{(' ' + digest) if digest else ''}",
                    }
                )
        return items
    if etype == "result":
        if ev.get("is_error") or ev.get("subtype") not in (None, "success"):
            return [{"kind": "status", "text": f"[error] {ev.get('subtype', 'error')}"}]
        return [{"kind": "status", "text": "[done]"}]
    return []  # system/init and unknown types carry no display value


def format_event(raw: str) -> list[dict[str, str]]:
    """Parse one NDJSON line into display items; non-JSON passes through verbatim."""
    raw = raw.rstrip("\n")
    if not raw.strip():
        return []
    try:
        ev = json.loads(raw)
    except json.JSONDecodeError:
        return [{"kind": "text", "text": raw}]  # defensive passthrough
    if not isinstance(ev, dict):
        return []
    return format_parsed(ev)


def _tool_digest(inp: dict[str, Any]) -> str:
    """One-line arg digest for a tool_use event (e.g. the edited path or command)."""
    for key in ("file_path", "path", "pattern", "command", "url"):
        val = inp.get(key)
        if isinstance(val, str):
            return val.splitlines()[0] if val else ""
    return ""


class _Live:
    """Runtime state for a session with an in-flight turn (never persisted)."""

    def __init__(self) -> None:
        self.buffer: list[dict[str, Any]] = []  # current turn, for replay-on-connect
        self.subscriber: Queue[dict[str, Any] | None] | None = None
        self.push_guard = threading.Lock()
        self.proc: subprocess.Popen[str] | None = None
        self.stopping = False
        self.init_model: str | None = None

    def push(self, item: dict[str, Any]) -> None:
        with self.push_guard:
            self.buffer.append(item)
            if self.subscriber is not None:
                self.subscriber.put(item)

    def end(self) -> None:
        with self.push_guard:
            if self.subscriber is not None:
                self.subscriber.put(_END)

    def attach(self) -> tuple[list[dict[str, Any]], Queue[dict[str, Any] | None]]:
        """Snapshot the buffer and register a fresh subscriber queue atomically —
        a mid-turn refresh loses nothing and duplicates nothing."""
        with self.push_guard:
            q: Queue[dict[str, Any] | None] = Queue()
            self.subscriber = q
            return list(self.buffer), q


class SessionManager:
    """Create/resume/stop/close planning sessions; one in-flight turn per session
    and per repo (via the shared per-project lock)."""

    def __init__(self, state_dir: Path | None = None) -> None:
        self._dir = (state_dir or registry.state_home()) / "sessions"
        self._live: dict[str, _Live] = {}
        self._guard = threading.Lock()

    # --- persistence -----------------------------------------------------------

    def _meta_path(self, sid: str) -> Path:
        return self._dir / f"{sid}.json"

    def _transcript_path(self, sid: str) -> Path:
        return self._dir / f"{sid}.ndjson"

    def _load(self, sid: str) -> dict[str, Any]:
        path = self._meta_path(sid)
        if not path.is_file():
            raise KeyError(sid)
        return registry.read_json(path)

    def meta(self, sid: str) -> dict[str, Any]:
        """One session's persisted meta (no transcript). KeyError when unknown."""
        return self._load(sid)

    def _save(self, meta: dict[str, Any]) -> None:
        registry.atomic_write_json(self._meta_path(meta["id"]), meta)

    def _append_transcript(self, sid: str, ev: dict[str, Any]) -> None:
        path = self._transcript_path(sid)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8", newline="") as fh:
            fh.write(json.dumps(ev) + "\n")

    def _append_raw(self, sid: str, raw: str) -> None:
        path = self._transcript_path(sid)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8", newline="") as fh:
            fh.write(raw.rstrip("\n") + "\n")

    def _transition(self, meta: dict[str, Any], to: str) -> None:
        edge = (meta["status"], to)
        if edge not in ALLOWED:
            raise locks.Conflict(
                "invalid_state",
                f"session {meta['id']} is {meta['status']!r}; cannot go {to!r}",
            )
        meta["status"] = to
        self._save(meta)

    # --- queries ----------------------------------------------------------------

    def list_sessions(self, project: str | None = None) -> list[dict[str, Any]]:
        """Session metas (no transcript), newest first, optionally per project."""
        if not self._dir.is_dir():
            return []
        metas: list[dict[str, Any]] = []
        for path in self._dir.glob("ps_*.json"):
            meta = registry.read_json(path)
            if project is None or meta.get("project") == project:
                metas.append(meta)
        metas.sort(key=lambda m: str(m.get("created_at", "")), reverse=True)
        return metas

    def streaming_count(self, project: str) -> int:
        """How many of PROJECT's sessions are mid-turn (board pulse dot)."""
        return sum(
            1 for m in self.list_sessions(project) if m.get("status") == "streaming"
        )

    def get(self, sid: str) -> dict[str, Any]:
        """Meta + the full transcript rendered to display entries [{n, kind, text}]."""
        meta = self._load(sid)
        entries: list[dict[str, Any]] = []
        path = self._transcript_path(sid)
        n = 0
        if path.is_file():
            for raw in path.read_text(encoding="utf-8").splitlines():
                if not raw.strip():
                    continue
                try:
                    ev = json.loads(raw)
                except json.JSONDecodeError:
                    entries.append({"n": n, "kind": "text", "text": raw})
                    continue
                if not isinstance(ev, dict):
                    continue
                etype = ev.get("type")
                if etype == "roundtable_user":
                    n = int(ev.get("n", n))
                    entries.append({"n": n, "kind": "user", "text": ev.get("text", "")})
                elif etype == "roundtable_interrupted":
                    entries.append({"n": n, "kind": "status", "text": "[interrupted]"})
                elif etype == "roundtable_stopped":
                    entries.append({"n": n, "kind": "status", "text": "[stopped]"})
                else:
                    for item in format_parsed(ev):
                        entries.append({"n": n, **item})
        return {**meta, "transcript": entries}

    # --- lifecycle ----------------------------------------------------------------

    def create(self, project: Project, prompt: str) -> dict[str, Any]:
        """Create a session (the explicit resource-creation act) and run turn 1.

        Returns the meta immediately — the UI navigates to the session view and
        attaches SSE while the turn streams.
        """
        meta: dict[str, Any] = {
            "id": new_id("ps"),
            "project": project.name,
            "claude_session_id": None,
            "status": "streaming",
            "created_at": now_iso(),
            "turns": [],
            "cost_est_usd": None,
            "produced_plans": [],
        }
        self._save(meta)
        first = project.planning_template.format(
            request=prompt, planning_dir=project.planning_dir
        )
        self._start_turn(project, meta, first, n=1, user_text=prompt)
        return meta

    def message(self, project: Project, sid: str, prompt: str) -> dict[str, Any]:
        """Follow-up turn (`--resume`); 409 unless the session is idle."""
        meta = self._load(sid)
        self._transition(meta, "streaming")  # 409 while streaming/closed/failed
        n = len(meta["turns"]) + 1
        self._start_turn(project, meta, prompt, n=n, user_text=prompt)
        return meta

    def stop(self, sid: str) -> dict[str, Any]:
        """Kill the in-flight turn; the turn thread finishes bookkeeping -> idle."""
        meta = self._load(sid)
        if meta["status"] != "streaming":
            raise locks.Conflict(
                "invalid_state", f"session {sid} is {meta['status']!r}, not streaming"
            )
        live = self._live.get(sid)
        if live is not None:
            live.stopping = True
            if live.proc is not None:
                stop_process(live.proc)
        self._append_transcript(sid, {"type": "roundtable_stopped"})
        return meta

    def close(self, sid: str) -> dict[str, Any]:
        """idle -> closed (terminal)."""
        meta = self._load(sid)
        self._transition(meta, "closed")
        return meta

    def recover(self) -> int:
        """Startup recovery: any meta stuck `streaming` at boot -> idle with a
        synthetic `interrupted` transcript event (no orphan claude process can be
        ours — we died). Returns the number recovered."""
        fixed = 0
        for meta in self.list_sessions():
            if meta.get("status") == "streaming":
                meta["status"] = "idle"
                self._save(meta)
                self._append_transcript(meta["id"], {"type": "roundtable_interrupted"})
                fixed += 1
        return fixed

    # --- streaming ----------------------------------------------------------------

    def attach(self, sid: str, keepalive: float = 15.0) -> Iterator[tuple[str, Any]]:
        """SSE feed for the in-flight turn: replays the current turn's buffered lines
        on connect, then live items; ('keepalive', None) every 15s idle; ends with
        ('end', status). A non-streaming session ends immediately."""
        meta = self._load(sid)
        live = self._live.get(sid)
        if meta["status"] != "streaming" or live is None:
            yield ("end", meta["status"])
            return
        buffered, q = live.attach()
        for item in buffered:
            yield ("data", item)
        while True:
            try:
                queued = q.get(timeout=keepalive)
            except Empty:
                yield ("keepalive", None)
                continue
            if queued is _END:
                break
            yield ("data", queued)
        yield ("end", self._load(sid)["status"])

    # --- the turn thread ------------------------------------------------------------

    def _start_turn(
        self,
        project: Project,
        meta: dict[str, Any],
        prompt: str,
        n: int,
        user_text: str,
    ) -> None:
        with self._guard:
            live = _Live()
            self._live[meta["id"]] = live
        thread = threading.Thread(
            target=self._run_turn,
            args=(project, meta, prompt, n, user_text, live),
            daemon=True,
        )
        thread.start()

    def _finish(self, meta: dict[str, Any], to: str, live: _Live) -> None:
        self._transition(meta, to)
        live.end()

    def _run_turn(
        self,
        project: Project,
        meta: dict[str, Any],
        prompt: str,
        n: int,
        user_text: str,
        live: _Live,
    ) -> None:
        sid: str = meta["id"]
        if not locks.try_acquire(project.path, f"planning session {sid}"):
            held = locks.holder(project.path) or "another task"
            live.push(
                {
                    "kind": "error",
                    "code": "repo_busy",
                    "text": f"repo is busy ({held}) — try again when it finishes",
                }
            )
            self._finish(meta, "idle", live)
            return
        result_event: dict[str, Any] | None = None
        spawn_failed = False
        try:
            before = plans.snapshot(project)
            self._append_transcript(
                sid, {"type": "roundtable_user", "n": n, "text": user_text}
            )
            live.push({"kind": "user", "text": user_text})
            cmd = build_claude_cmd(project, project.planning_permission_mode)
            if cmd is None:
                live.push(
                    {
                        "kind": "error",
                        "code": "claude_bin",
                        "text": f"claude_bin {project.claude_bin!r} not found",
                    }
                )
                spawn_failed = True
                return
            if n > 1 and meta.get("claude_session_id"):
                cmd += ["--resume", str(meta["claude_session_id"])]
            try:
                proc = spawn_claude(cmd, project.path, prompt)
            except OSError as exc:
                live.push({"kind": "error", "code": "spawn", "text": str(exc)})
                spawn_failed = True
                return
            live.proc = proc
            stdout: IO[str] = proc.stdout  # type: ignore[assignment]  # PIPE guarantees
            for raw in stdout:
                if not raw.strip():
                    continue
                self._append_raw(sid, raw)
                try:
                    ev = json.loads(raw)
                except json.JSONDecodeError:
                    live.push({"kind": "text", "text": raw.rstrip("\n")})
                    continue
                if not isinstance(ev, dict):
                    continue
                if ev.get("type") == "system" and ev.get("subtype") == "init":
                    live.init_model = ev.get("model")
                    if not meta.get("claude_session_id") and ev.get("session_id"):
                        meta["claude_session_id"] = ev["session_id"]
                        self._save(meta)
                    continue
                if ev.get("type") == "result":
                    result_event = ev
                for item in format_parsed(ev):
                    live.push(item)
            proc.wait()
        finally:
            locks.release(project.path)
            if spawn_failed:
                self._finish(meta, "failed", live)
                return
            after = plans.snapshot(project)
            known = {p["slug"] for p in meta["produced_plans"]}
            for slug in plans.snapshot_diff(before, after):
                if slug not in known:
                    meta["produced_plans"].append({"slug": slug, "turn": n})
            cost = (
                costs.extract(result_event, project.model or live.init_model)
                if result_event is not None
                else {"usage": None, "cost_est_usd": None, "cost_reported_usd": None}
            )
            meta["turns"].append({"n": n, **cost})
            est = [
                t["cost_est_usd"]
                for t in meta["turns"]
                if t.get("cost_est_usd") is not None
            ]
            meta["cost_est_usd"] = sum(est) if est else None
            # A model refusal is still a valid turn: failed only on rc!=0 with no
            # result event (and never for a user-initiated stop).
            failed = proc.returncode != 0 and result_event is None and not live.stopping
            self._finish(meta, "failed" if failed else "idle", live)


# Executor (ITER_03) shares these; re-exported for one import site.
__all__ = [
    "ALLOWED",
    "STATUSES",
    "SessionManager",
    "build_claude_cmd",
    "format_event",
    "format_parsed",
    "new_id",
    "now_iso",
    "resolve_bin",
    "spawn_claude",
    "stop_process",
]
