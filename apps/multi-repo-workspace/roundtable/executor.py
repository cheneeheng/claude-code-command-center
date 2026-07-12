"""End-Turn batch runner: one thread per distinct project, orders of a project run
in queue order (sequential within a repo, concurrent across repos).

Output NDJSON files are the durable record — SSE queues are in-memory only and
vanish on restart; `read_output` serves replay live and after restart.
"""

from __future__ import annotations

import json
import subprocess
import threading
from queue import Empty, Queue
from typing import Any, Iterator

from roundtable import costs, locks, tracker
from roundtable.locks import Conflict
from roundtable.registry import Project
from roundtable.rounds import RoundStore
from roundtable.sessions import (
    build_claude_cmd,
    format_parsed,
    spawn_claude,
    stop_process,
)

_END = None


def resolve_instruction(project: Project, slug: str, override: str | None) -> str:
    """The stdin instruction that NAMES the plan file ({path} substituted); the plan
    body is never piped. Precedence: per-order override -> project template."""
    path = f"{project.planning_dir}/{slug}.md"
    template = override or project.instruction_template
    return template.format(path=path) if "{path}" in template else template


class _OrderLive:
    """In-memory live feed for one running order (replay buffer + one subscriber)."""

    def __init__(self) -> None:
        self.buffer: list[str] = []
        self.subscriber: Queue[str | None] | None = None
        self.guard = threading.Lock()

    def push(self, line: str) -> None:
        with self.guard:
            self.buffer.append(line)
            if self.subscriber is not None:
                self.subscriber.put(line)

    def end(self) -> None:
        with self.guard:
            if self.subscriber is not None:
                self.subscriber.put(_END)

    def attach(self) -> tuple[list[str], Queue[str | None]]:
        with self.guard:
            q: Queue[str | None] = Queue()
            self.subscriber = q
            return list(self.buffer), q


class Executor:
    """Runs one round's orders. `start` returns immediately; threads settle order
    states through the RoundStore (the one mutation path) and flip the round to
    review when the last terminal order lands."""

    def __init__(self, store: RoundStore) -> None:
        self._store = store
        self._live: dict[str, _OrderLive] = {}
        self._procs: dict[str, subprocess.Popen[str]] = {}
        self._guard = threading.Lock()
        self._stop = False

    # --- lifecycle -----------------------------------------------------------------

    def start(self, projects: dict[str, Project], rnd: dict[str, Any]) -> None:
        self._stop = False
        rid: str = rnd["id"]
        by_project: dict[str, list[dict[str, Any]]] = {}
        for order in rnd["orders"]:
            if order["state"] == "queued":
                by_project.setdefault(order["project"], []).append(order)
        if not by_project:  # everything was skipped at end_turn
            self._store.maybe_finish(rid)
            return
        for name, orders in by_project.items():
            threading.Thread(
                target=self._run_project_batch,
                args=(projects[name], rid, orders),
                daemon=True,
            ).start()

    def stop(self) -> None:
        """Signal stop and terminate in-flight processes; threads settle the orders
        as `stopped`, the store's stop() drains queued -> skipped."""
        self._stop = True
        with self._guard:
            procs = list(self._procs.values())
        for proc in procs:
            stop_process(proc)

    # --- streaming -------------------------------------------------------------------

    def attach(
        self, rid: str, oid: str, state: str, keepalive: float = 15.0
    ) -> Iterator[tuple[str, Any]]:
        """SSE feed: live replay+follow while running, else the persisted file."""
        live = self._live.get(oid)
        if live is None:
            for line in self._store.read_output(rid, oid):
                yield ("data", line)
            yield ("end", state)
            return
        buffered, q = live.attach()
        for line in buffered:
            yield ("data", line)
        while True:
            try:
                item = q.get(timeout=keepalive)
            except Empty:
                yield ("keepalive", None)
                continue
            if item is _END:
                break
            yield ("data", item)
        yield ("end", self._order_state(oid))

    def _order_state(self, oid: str) -> str:
        try:
            _, order = self._store.find_order(oid)
            return str(order["state"])
        except KeyError:
            return "unknown"

    # --- the per-project batch ----------------------------------------------------------

    def _emit(self, rid: str, oid: str, line: str) -> None:
        self._store.append_output(rid, oid, line)
        live = self._live.get(oid)
        if live is not None:
            live.push(line)

    def _skip(self, rid: str, oid: str, reason: str) -> None:
        try:
            self._store.order_terminal(rid, oid, "skipped")
        except Conflict:
            return  # already settled by a concurrent stop
        self._emit(rid, oid, f"[roundtable] skipped: {reason}")
        # A skipped order never reached _run_order, so it has no live feed to end;
        # attach() serves its output file directly.

    def _run_project_batch(
        self, project: Project, rid: str, orders: list[dict[str, Any]]
    ) -> None:
        failed = False
        for order in orders:
            oid: str = order["id"]
            if self._stop:
                self._skip(rid, oid, "round stopped")
            elif failed:
                # Stop-on-failure within a project; cross-project unaffected.
                self._skip(rid, oid, "an earlier order in this project failed")
            else:
                state = self._run_order(project, rid, order)
                if state in ("failed", "stopped"):
                    failed = True
            self._store.maybe_finish(rid)

    def _run_order(self, project: Project, rid: str, order: dict[str, Any]) -> str:
        oid: str = order["id"]
        live = _OrderLive()
        with self._guard:
            self._live[oid] = live

        # Preflight the binary BEFORE touching status / taking the lock — a bad
        # claude_bin must not strand the plan as 'running' (docket decision).
        cmd = build_claude_cmd(project, project.permission_mode)
        if cmd is None:
            self._emit(
                rid, oid, f"[roundtable] claude_bin {project.claude_bin!r} not found"
            )
            return self._settle(rid, oid, live, "failed", rc=None)

        if locks.is_held(project.path):
            holder = locks.holder(project.path) or "another task"
            self._emit(rid, oid, f"[roundtable] waiting for repo ({holder})")
        locks.acquire(project.path, f"order {oid}")  # blocking: planning turn first
        init_model: str | None = None
        result_event: dict[str, Any] | None = None
        rc: int | None = None
        try:
            tracker.set_status(
                project, order["slug"], "running", trigger="round", run_id=oid
            )
            self._store.order_running(rid, oid)
            instruction = resolve_instruction(
                project, order["slug"], order.get("instruction")
            )
            try:
                proc = spawn_claude(cmd, project.path, instruction)
            except OSError as exc:
                self._emit(rid, oid, f"[roundtable] spawn failed: {exc}")
                tracker.set_status(
                    project, order["slug"], "ready", trigger="round", run_id=oid
                )
                return self._settle(rid, oid, live, "failed", rc=None)
            with self._guard:
                self._procs[oid] = proc
            assert proc.stdout is not None  # PIPE guarantees a stream
            for raw in proc.stdout:
                if not raw.strip():
                    continue
                try:
                    ev = json.loads(raw)
                except json.JSONDecodeError:
                    self._emit(rid, oid, raw.rstrip("\n"))
                    continue
                if not isinstance(ev, dict):
                    continue
                if ev.get("type") == "system" and ev.get("subtype") == "init":
                    init_model = ev.get("model")
                    continue
                if ev.get("type") == "result":
                    result_event = ev
                for item in format_parsed(ev):
                    self._emit(rid, oid, item["text"])
            proc.wait()
            rc = proc.returncode
        finally:
            with self._guard:
                self._procs.pop(oid, None)
            locks.release(project.path)

        stopped = self._stop
        if stopped:
            state = "stopped"
        else:
            state = "succeeded" if rc == 0 else "failed"
        tracker.set_status(
            project,
            order["slug"],
            "implemented" if state == "succeeded" else "ready",
            trigger="round",
            run_id=oid,
            rc=rc,
        )
        cost = (
            costs.extract(result_event, project.model or init_model)
            if result_event is not None
            else {"usage": None, "cost_est_usd": None, "cost_reported_usd": None}
        )
        self._emit(
            rid,
            oid,
            f"[roundtable] run {'completed' if state == 'succeeded' else state}"
            + (f" (rc={rc})" if rc not in (0, None) else ""),
        )
        return self._settle(rid, oid, live, state, rc=rc, **cost)

    def _settle(
        self,
        rid: str,
        oid: str,
        live: _OrderLive,
        state: str,
        **fields: Any,
    ) -> str:
        try:
            self._store.order_terminal(rid, oid, state, **fields)
        except Conflict:
            pass  # already settled (stop/recovery race); keep the recorded state
        with self._guard:
            self._live.pop(oid, None)  # terminal: replay now serves from the file
        live.end()
        return state
