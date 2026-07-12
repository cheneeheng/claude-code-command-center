"""Round store + state machines + orders. One JSON file per round under
~/.roundtable/rounds/; order output NDJSON lives in rounds/<rnd_id>/<ord_id>.ndjson.

Invariant: at most one round with status != done; closing a round auto-opens the
next. `number` assignment and every round-file read-modify-write happen under the
process-wide `locks.rounds_lock` (single process; max(number)+1 is safe under it —
the sequential-ID race is bounded to this process by design).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from roundtable import locks, plans, registry, tracker
from roundtable.locks import Conflict
from roundtable.plans import safe_slug
from roundtable.registry import Project
from roundtable.sessions import new_id, now_iso

ROUND_ALLOWED: dict[tuple[str, str], set[str]] = {  # (from, to): {triggers}
    ("open", "executing"): {"end_turn"},
    ("executing", "review"): {"all_terminal", "stop", "startup_reset"},
    ("review", "done"): {"close"},
}
ROUND_STATUSES = ("open", "executing", "review", "done")

ORDER_ALLOWED: set[tuple[str, str]] = {
    ("queued", "running"),
    ("queued", "failed"),  # claude_bin preflight fails before the order ever runs
    ("running", "succeeded"),
    ("running", "failed"),
    ("running", "stopped"),
    ("queued", "skipped"),
}
ORDER_TERMINAL = ("succeeded", "failed", "stopped", "skipped")

FOLLOWUP_CAP = 2048  # 2 KB free-text note cap


class RoundStore:
    """All round/order mutations go through here (one mutation path per aggregate)."""

    def __init__(self, state_dir: Path | None = None) -> None:
        self._dir = (state_dir or registry.state_home()) / "rounds"

    # --- persistence -------------------------------------------------------------

    def _path(self, rid: str) -> Path:
        return self._dir / f"{rid}.json"

    def output_path(self, rid: str, oid: str) -> Path:
        return self._dir / rid / f"{oid}.ndjson"

    def _load(self, rid: str) -> dict[str, Any]:
        path = self._path(rid)
        if not path.is_file():
            raise KeyError(rid)
        return registry.read_json(path)

    def _save(self, rnd: dict[str, Any]) -> None:
        registry.atomic_write_json(self._path(rnd["id"]), rnd)

    def _all(self) -> list[dict[str, Any]]:
        if not self._dir.is_dir():
            return []
        rounds = [registry.read_json(p) for p in self._dir.glob("rnd_*.json")]
        rounds.sort(key=lambda r: int(r["number"]), reverse=True)
        return rounds

    # --- read views (cost computed at read time, never stored) --------------------

    @staticmethod
    def _with_cost(rnd: dict[str, Any]) -> dict[str, Any]:
        est = [
            o["cost_est_usd"]
            for o in rnd["orders"]
            if o.get("cost_est_usd") is not None
        ]
        return {**rnd, "cost_est_usd": sum(est) if est else None}

    def list_rounds(self) -> list[dict[str, Any]]:
        """Round history, newest first, costs computed."""
        return [self._with_cost(r) for r in self._all()]

    def get(self, rid: str) -> dict[str, Any]:
        return self._with_cost(self._load(rid))

    def current(self) -> dict[str, Any]:
        """The one non-done round; created lazily as Round #1 on first boot."""
        with locks.rounds_lock:
            return self._with_cost(self._current_locked())

    def _current_locked(self) -> dict[str, Any]:
        rounds = self._all()
        open_rounds = [r for r in rounds if r["status"] != "done"]
        if len(open_rounds) > 1:  # enforce the at-most-one invariant loudly
            raise Conflict(
                "invariant", f"{len(open_rounds)} non-done rounds on disk; expected 1"
            )
        if open_rounds:
            return open_rounds[0]
        rnd = self._new_round(number=1, carried=[])
        self._save(rnd)
        return rnd

    @staticmethod
    def _new_round(number: int, carried: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "id": new_id("rnd"),
            "number": number,
            "status": "open",
            "created_at": now_iso(),
            "executed_at": None,
            "closed_at": None,
            "orders": [],
            "carried_followups": carried,
        }

    def find_order(self, oid: str) -> tuple[dict[str, Any], dict[str, Any]]:
        """(round, order) for OID across all rounds. KeyError when unknown."""
        for rnd in self._all():
            for order in rnd["orders"]:
                if order["id"] == oid:
                    return rnd, order
        raise KeyError(oid)

    # --- transitions ---------------------------------------------------------------

    def _round_transition(self, rnd: dict[str, Any], to: str, trigger: str) -> None:
        edge = (rnd["status"], to)
        if edge not in ROUND_ALLOWED or trigger not in ROUND_ALLOWED[edge]:
            raise Conflict(
                "invalid_state",
                f"round {rnd['number']} is {rnd['status']!r}; "
                f"cannot go {to!r} (trigger {trigger!r})",
            )
        rnd["status"] = to

    @staticmethod
    def _order_transition(order: dict[str, Any], to: str) -> None:
        if (order["state"], to) not in ORDER_ALLOWED:
            raise Conflict(
                "invalid_state", f"order is {order['state']!r}; cannot go {to!r}"
            )
        order["state"] = to

    # --- open-phase mutations --------------------------------------------------------

    def add_order(
        self, project: Project, slug: str, instruction: str | None
    ) -> dict[str, Any]:
        """Queue an order in the open round. Plan must exist and be `ready`
        (only-ready-is-runnable, docket decision); no duplicate (project, slug)."""
        slug = safe_slug(slug)
        if not (plans.planning_root(project) / f"{slug}.md").is_file():
            raise FileNotFoundError(f"plan not found: {project.name}/{slug}")
        status = tracker.read_record(project, slug)["status"]
        if status != "ready":
            raise Conflict(
                "not_ready", f"{project.name}/{slug} is {status!r}, not runnable"
            )
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "open":
                raise Conflict("invalid_state", f"round is {rnd['status']!r}, not open")
            if any(
                o["project"] == project.name and o["slug"] == slug
                for o in rnd["orders"]
            ):
                raise Conflict(
                    "duplicate", f"{project.name}/{slug} is already in this round"
                )
            order: dict[str, Any] = {
                "id": new_id("ord"),
                "project": project.name,
                "slug": slug,
                "instruction": instruction,
                "state": "queued",
                "rc": None,
                "usage": None,
                "cost_est_usd": None,
                "cost_reported_usd": None,
                "reviewed": False,
                "followup": None,
            }
            rnd["orders"].append(order)
            self._save(rnd)
            return order

    def remove_order(self, oid: str) -> None:
        """Remove an order; only while the round is open."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "open":
                raise Conflict("invalid_state", f"round is {rnd['status']!r}, not open")
            if not any(o["id"] == oid for o in rnd["orders"]):
                raise KeyError(oid)
            rnd["orders"] = [o for o in rnd["orders"] if o["id"] != oid]
            self._save(rnd)

    def set_instruction(self, oid: str, instruction: str | None) -> dict[str, Any]:
        """Per-order instruction override, set in the round view while open."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "open":
                raise Conflict("invalid_state", f"round is {rnd['status']!r}, not open")
            order = self._order_in(rnd, oid)
            order["instruction"] = instruction or None
            self._save(rnd)
            return order

    @staticmethod
    def _order_in(rnd: dict[str, Any], oid: str) -> dict[str, Any]:
        orders: list[dict[str, Any]] = rnd["orders"]
        for order in orders:
            if order["id"] == oid:
                return order
        raise KeyError(oid)

    def dismiss_followup(self, index: int) -> None:
        """Drop one carried follow-up from the open round (review-panel Dismiss)."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "open":
                raise Conflict("invalid_state", f"round is {rnd['status']!r}, not open")
            carried = rnd["carried_followups"]
            if not 0 <= index < len(carried):
                raise KeyError(str(index))
            del carried[index]
            self._save(rnd)

    # --- execution-phase transitions ---------------------------------------------------

    def end_turn(self, projects: dict[str, Project]) -> dict[str, Any]:
        """open -> executing. Re-validates every order's plan is still `ready`;
        stale orders flip to `skipped` rather than failing the whole turn."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "open":
                raise Conflict("invalid_state", f"round is {rnd['status']!r}, not open")
            if not rnd["orders"]:
                raise ValueError("round has no orders")
            self._round_transition(rnd, "executing", "end_turn")
            rnd["executed_at"] = now_iso()
            for order in rnd["orders"]:
                project = projects.get(order["project"])
                status = (
                    tracker.read_record(project, order["slug"])["status"]
                    if project is not None
                    else None
                )
                if status != "ready":
                    self._order_transition(order, "skipped")
                    self.append_output(
                        rnd["id"],
                        order["id"],
                        f"[roundtable] skipped: plan is {status!r}, not ready",
                    )
            self._save(rnd)
            return rnd

    def order_running(self, rid: str, oid: str) -> None:
        with locks.rounds_lock:
            rnd = self._load(rid)
            self._order_transition(self._order_in(rnd, oid), "running")
            self._save(rnd)

    def order_terminal(self, rid: str, oid: str, state: str, **fields: Any) -> None:
        """Write an order's terminal state (+ rc/usage/costs) in one mutation."""
        with locks.rounds_lock:
            rnd = self._load(rid)
            order = self._order_in(rnd, oid)
            self._order_transition(order, state)
            order.update(fields)
            self._save(rnd)

    def maybe_finish(self, rid: str) -> bool:
        """Flip executing -> review (trigger all_terminal) when the last order lands."""
        with locks.rounds_lock:
            rnd = self._load(rid)
            if rnd["status"] != "executing":
                return False
            if not all(o["state"] in ORDER_TERMINAL for o in rnd["orders"]):
                return False
            self._round_transition(rnd, "review", "all_terminal")
            self._save(rnd)
            return True

    def stop(self) -> dict[str, Any]:
        """executing -> review (trigger stop). The executor terminates processes and
        settles order states before this is called with settled=True semantics; here
        we drain anything still queued."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            if rnd["status"] != "executing":
                raise Conflict(
                    "invalid_state", f"round is {rnd['status']!r}, not executing"
                )
            for order in rnd["orders"]:
                if order["state"] == "queued":
                    self._order_transition(order, "skipped")
            self._round_transition(rnd, "review", "stop")
            self._save(rnd)
            return rnd

    def recover(self) -> bool:
        """Startup recovery: a round stuck `executing` at boot -> every running order
        `stopped` (rc null), queued -> `skipped`, round -> review (startup_reset)."""
        with locks.rounds_lock:
            rounds = self._all()
            stuck = next((r for r in rounds if r["status"] == "executing"), None)
            if stuck is None:
                return False
            for order in stuck["orders"]:
                if order["state"] == "running":
                    self._order_transition(order, "stopped")
                elif order["state"] == "queued":
                    self._order_transition(order, "skipped")
            self._round_transition(stuck, "review", "startup_reset")
            self._save(stuck)
            return True

    # --- review-phase mutations (ITER_04) ------------------------------------------------

    def _review_order(self, oid: str) -> tuple[dict[str, Any], dict[str, Any]]:
        rnd = self._current_locked()
        if rnd["status"] != "review":
            raise Conflict("invalid_state", f"round is {rnd['status']!r}, not review")
        return rnd, self._order_in(rnd, oid)

    def set_reviewed(self, oid: str, flag: bool) -> dict[str, Any]:
        with locks.rounds_lock:
            rnd, order = self._review_order(oid)
            order["reviewed"] = bool(flag)
            self._save(rnd)
            return order

    def set_followup(self, oid: str, note: str) -> dict[str, Any]:
        with locks.rounds_lock:
            rnd, order = self._review_order(oid)
            trimmed = note.strip()
            if len(trimmed) > FOLLOWUP_CAP:
                raise ValueError(f"note exceeds {FOLLOWUP_CAP} bytes")
            order["followup"] = trimmed or None
            self._save(rnd)
            return order

    def close(self) -> dict[str, Any]:
        """review -> done; auto-open Round N+1 carrying every non-empty follow-up
        (plus the closing round's own carried items whose (project, slug) never got
        a new order — unaddressed agenda rolls forward, never silently drops)."""
        with locks.rounds_lock:
            rnd = self._current_locked()
            self._round_transition(rnd, "done", "close")
            rnd["closed_at"] = now_iso()
            carried: list[dict[str, Any]] = [
                {
                    "from_round": rnd["number"],
                    "project": o["project"],
                    "slug": o["slug"],
                    "note": o["followup"],
                }
                for o in rnd["orders"]
                if o.get("followup")
            ]
            ordered_keys = {(o["project"], o["slug"]) for o in rnd["orders"]}
            for item in rnd.get("carried_followups", []):
                if (item["project"], item["slug"]) not in ordered_keys:
                    carried.append(item)
            self._save(rnd)
            nxt = self._new_round(number=int(rnd["number"]) + 1, carried=carried)
            self._save(nxt)
            return nxt

    # --- order output ------------------------------------------------------------------

    def append_output(self, rid: str, oid: str, line: str) -> None:
        """Append one display line to the order's durable NDJSON output."""
        path = self.output_path(rid, oid)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8", newline="") as fh:
            fh.write(json.dumps({"line": line}) + "\n")

    def read_output(self, rid: str, oid: str) -> list[str]:
        """The persisted output lines (works live and after restart)."""
        path = self.output_path(rid, oid)
        if not path.is_file():
            return []
        lines: list[str] = []
        for raw in path.read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            try:
                lines.append(str(json.loads(raw)["line"]))
            except (json.JSONDecodeError, KeyError):
                lines.append(raw)
        return lines
