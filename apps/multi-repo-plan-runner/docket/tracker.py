"""Implementation sidecar: lifecycle status + transition history. docket OWNS these.

One JSON file per plan under <repo>/.agents_workspace/implementation/<slug>.json,
mirroring the plan's relative path. A missing sidecar means `ready` with empty history.
"""

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

VALID_STATUS = ("ready", "running", "implemented")

ALLOWED = {  # (from, to): {triggers}  — the full lifecycle table from SKELETON §02
    ("ready", "running"): {"headless"},
    ("running", "implemented"): {"headless"},
    ("running", "ready"): {"headless", "startup_reset"},
    ("ready", "implemented"): {"manual"},
    ("implemented", "ready"): {"manual"},
}


def sidecar_path(project, slug: str) -> Path:
    """<repo>/<implementation_dir>/<slug>.json — mirrors the plan's path."""
    return Path(project.path) / project.implementation_dir / f"{slug}.json"


def read_record(project, slug: str) -> dict:
    """Load the sidecar JSON. Missing file -> {slug, status:"ready", history:[]}.

    An unrecognised status is defensively treated as `ready`.
    """
    path = sidecar_path(project, slug)
    if not path.is_file():
        return {"slug": slug, "status": "ready", "history": []}
    try:
        rec = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"slug": slug, "status": "ready", "history": []}
    if rec.get("status") not in VALID_STATUS:
        rec["status"] = "ready"
    rec.setdefault("slug", slug)
    rec.setdefault("history", [])
    return rec


def set_status(
    project,
    slug: str,
    to: str,
    *,
    trigger: str,
    run_id: str | None = None,
    rc: int | None = None,
) -> dict:
    """Validate (current, to) against ALLOWED + the trigger, append a history record,
    and atomically write the sidecar. Returns the updated record. Raises ValueError on an
    illegal transition or disallowed trigger."""
    rec = read_record(project, slug)
    current = rec["status"]

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

    _atomic_write(sidecar_path(project, slug), rec)
    return rec


def _atomic_write(path: Path, rec: dict) -> None:
    """Write to a temp file in the same directory, then os.replace over the target."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    tmp.write_text(json.dumps(rec, indent=2), encoding="utf-8")
    # On Windows a just-written target can be transiently locked by AV/indexer, making the
    # atomic os.replace fail with PermissionError; retry briefly before giving up.
    for _ in range(9):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.05)
    os.replace(tmp, path)  # final attempt; let a persistent PermissionError propagate


def reset_stale_runs(projects) -> list:
    """Startup recovery: flip every sidecar reading `running` back to `ready`
    (trigger=startup_reset). In-memory runs die with the process, so any persisted
    `running` is orphaned. Returns the list of (project_name, slug) reset."""
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
