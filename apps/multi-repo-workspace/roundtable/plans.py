"""Plan discovery + read: planning/**/*.md -> Plan views. Plans are read-only.

Cross-reference: forked at birth from docket (apps/multi-repo-plan-runner/docket/core.py)
plan discovery; only the sidecar format is a kept-in-sync contract (see tracker.py).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from roundtable import frontmatter, tracker
from roundtable.registry import Project

_SEGMENT = re.compile(r"^[A-Za-z0-9._-]+$")


@dataclass
class Plan:
    project: str
    slug: str  # relative path under planning/, sans .md; may contain "/"
    title: str
    status: str  # ready|running|implemented — sourced from the sidecar, NOT the plan
    body: str = ""  # "" for list summaries; full markdown from read_plan
    history: list[dict[str, Any]] = field(default_factory=list)
    mtime: int = 0  # plan file st_mtime (s) — the Plans tab's "updated" column


def safe_slug(slug: str) -> str:
    """Validate a plan slug used as both a relative path and a URL/query value.

    Accept one or more `/`-separated segments each matching ^[A-Za-z0-9._-]+$;
    reject `.`/`..` segments, leading/trailing `/`, empty slugs, and absolute paths.
    Makes it impossible to escape planning/. Returns the slug unchanged on success.
    """
    if not slug or slug.startswith("/") or slug.endswith("/"):
        raise ValueError(f"invalid slug: {slug!r}")
    for seg in slug.split("/"):
        if seg in ("", ".", "..") or not _SEGMENT.match(seg):
            raise ValueError(f"invalid slug segment {seg!r} in {slug!r}")
    return slug


def planning_root(project: Project) -> Path:
    return Path(project.path) / project.planning_dir


def list_plans(project: Project) -> list[Plan]:
    """Recursively discover planning/**/*.md -> Plan summaries (body=""), sorted."""
    root = planning_root(project)
    if not root.is_dir():
        return []

    plans: list[Plan] = []
    for md in root.rglob("*.md"):
        if not md.is_file():
            continue
        slug = md.relative_to(root).with_suffix("").as_posix()
        meta, _ = frontmatter.parse(md.read_text(encoding="utf-8"))
        status = tracker.read_record(project, slug)["status"]
        plans.append(
            Plan(
                project=project.name,
                slug=slug,
                title=meta.get("title") or slug,
                status=status,
                mtime=int(md.stat().st_mtime),
            )
        )
    plans.sort(key=lambda p: (p.status, p.slug))
    return plans


def plan_counts(project: Project) -> dict[str, int]:
    """Plan counts by lifecycle status, for the board cards."""
    counts = {status: 0 for status in tracker.VALID_STATUS}
    for plan in list_plans(project):
        counts[plan.status] += 1
    return counts


def read_plan(project: Project, slug: str) -> Plan:
    """Full plan body + status + history. Missing file -> FileNotFoundError."""
    slug = safe_slug(slug)
    md = planning_root(project) / f"{slug}.md"
    if not md.is_file():
        raise FileNotFoundError(f"plan not found: {project.name}/{slug}")
    text = md.read_text(encoding="utf-8")
    meta, _ = frontmatter.parse(text)
    rec = tracker.read_record(project, slug)
    return Plan(
        project=project.name,
        slug=slug,
        title=meta.get("title") or slug,
        status=rec["status"],
        body=text,
        history=list(rec["history"]),
    )


def manual_command(project: Project, slug: str) -> str:
    """Copy-pasteable command for running the plan yourself (feeds the plan body)."""
    slug = safe_slug(slug)
    plan_rel = f"{project.planning_dir}/{slug}.md"
    return (
        f"cd {project.path} && claude -p < {plan_rel}\n"
        f"# or: cd {project.path} && claude   (then paste / @-mention the plan file)"
    )


def snapshot(project: Project) -> dict[str, tuple[int, int]]:
    """{slug: (mtime_ns, size)} for every plan file — the produced-plan detector's
    before/after probe (ITER_02)."""
    root = planning_root(project)
    if not root.is_dir():
        return {}
    out: dict[str, tuple[int, int]] = {}
    for md in root.rglob("*.md"):
        if not md.is_file():
            continue
        st = md.stat()
        slug = md.relative_to(root).with_suffix("").as_posix()
        out[slug] = (st.st_mtime_ns, st.st_size)
    return out


def snapshot_diff(
    before: dict[str, tuple[int, int]], after: dict[str, tuple[int, int]]
) -> list[str]:
    """Slugs new or changed between two snapshots, sorted."""
    return sorted(s for s, sig in after.items() if before.get(s) != sig)
