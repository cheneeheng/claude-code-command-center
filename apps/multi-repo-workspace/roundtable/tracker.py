"""Implementation sidecar: lifecycle status + transition history. The app OWNS these.

One JSON file per plan under <repo>/<implementation_dir>/<slug>.json, mirroring the
plan's relative path. A missing sidecar means `ready` with empty history.

Cross-reference: the on-disk sidecar format (keys, location, allowed statuses) is
byte-compatible with docket's (apps/multi-repo-plan-runner/docket/tracker.py) so both
apps can point at the same repos — registered in docs/shared-plugin-logic.md. Trigger
vocabularies differ (roundtable: round|manual|startup_reset; docket:
headless|manual|startup_reset); both sides treat `trigger` as an opaque display string.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from roundtable.registry import Project, atomic_write_json

VALID_STATUS = ("ready", "running", "implemented")

ALLOWED: dict[tuple[str, str], set[str]] = {  # (from, to): {triggers}
    ("ready", "running"): {"round"},
    ("running", "implemented"): {"round"},
    ("running", "ready"): {"round", "startup_reset"},
    ("ready", "implemented"): {"manual"},
    ("implemented", "ready"): {"manual"},
}


def sidecar_path(project: Project, slug: str) -> Path:
    """<repo>/<implementation_dir>/<slug>.json — mirrors the plan's path."""
    return Path(project.path) / project.implementation_dir / f"{slug}.json"


def read_record(project: Project, slug: str) -> dict[str, Any]:
    """Load the sidecar JSON. Missing file -> {slug, status:"ready", history:[]}.

    An unrecognised status is defensively treated as `ready`.
    """
    path = sidecar_path(project, slug)
    if not path.is_file():
        return {"slug": slug, "status": "ready", "history": []}
    try:
        rec: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"slug": slug, "status": "ready", "history": []}
    if rec.get("status") not in VALID_STATUS:
        rec["status"] = "ready"
    rec.setdefault("slug", slug)
    rec.setdefault("history", [])
    return rec


def set_status(
    project: Project,
    slug: str,
    to: str,
    *,
    trigger: str,
    run_id: str | None = None,
    rc: int | None = None,
) -> dict[str, Any]:
    """Validate (current, to) against ALLOWED + the trigger, append a history record,
    and atomically write the sidecar. Returns the updated record. Raises ValueError on
    an illegal transition or disallowed trigger."""
    rec = read_record(project, slug)
    current: str = rec["status"]

    edge = (current, to)
    if edge not in ALLOWED:
        raise ValueError(
            f"illegal transition {current!r} -> {to!r} for {project.name}/{slug}"
        )
    if trigger not in ALLOWED[edge]:
        raise ValueError(
            f"trigger {trigger!r} not allowed for {current!r} -> {to!r} "
            f"({project.name}/{slug})"
        )

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rec["status"] = to
    rec["slug"] = slug
    rec["history"].append(
        {
            "ts": ts,
            "from": current,
            "to": to,
            "trigger": trigger,
            "run_id": run_id,
            "rc": rc,
        }
    )

    atomic_write_json(sidecar_path(project, slug), rec)
    return rec


def reset_stale_runs(projects: list[Project]) -> list[tuple[str, str]]:
    """Startup recovery: flip every sidecar reading `running` back to `ready`
    (trigger=startup_reset). In-memory runs die with the process, so any persisted
    `running` is orphaned — docket-written ones included (same format). Returns the
    list of (project_name, slug) reset."""
    reset: list[tuple[str, str]] = []
    for project in projects:
        impl_root = Path(project.path) / project.implementation_dir
        if not impl_root.is_dir():
            continue
        for sidecar in impl_root.rglob("*.json"):
            slug = sidecar.relative_to(impl_root).with_suffix("").as_posix()
            rec = read_record(project, slug)
            if rec["status"] == "running":
                set_status(project, slug, "ready", trigger="startup_reset")
                reset.append((project.name, slug))
    return reset
