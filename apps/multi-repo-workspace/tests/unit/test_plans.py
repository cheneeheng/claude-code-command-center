"""plans: safe_slug traversal guard, discovery, read, snapshots."""

from __future__ import annotations

import pytest

from roundtable import plans, tracker
from tests.conftest import write_plan


@pytest.mark.parametrize("slug", ["a", "a/b", "A-1_x.y/z", "dir/sub/plan"])
def test_safe_slug_accepts(slug):
    assert plans.safe_slug(slug) == slug


@pytest.mark.parametrize(
    "slug",
    ["", "/abs", "trail/", "a//b", "..", "a/../b", ".", "a/./b", "a b", "a\\b", "a?"],
)
def test_safe_slug_rejects(slug):
    with pytest.raises(ValueError):
        plans.safe_slug(slug)


def test_list_plans_missing_dir(project, tmp_path):
    project.planning_dir = "does/not/exist"
    assert plans.list_plans(project) == []


def test_list_plans_titles_status_sorted(project):
    write_plan(project, "b-notitle", "# no fm\n")
    write_plan(project, "sub/a", "---\ntitle: Sub A\n---\nbody\n")
    tracker.set_status(project, "b-notitle", "implemented", trigger="manual")
    found = plans.list_plans(project)
    assert [(p.slug, p.title, p.status) for p in found] == [
        ("b-notitle", "b-notitle", "implemented"),
        ("sub/a", "Sub A", "ready"),
    ]
    assert all(p.body == "" for p in found)
    assert all(p.mtime > 0 for p in found)


def test_plan_counts(project):
    write_plan(project, "one")
    write_plan(project, "two")
    tracker.set_status(project, "two", "implemented", trigger="manual")
    assert plans.plan_counts(project) == {"ready": 1, "running": 0, "implemented": 1}


def test_read_plan_full(project, plan_file):
    plan = plans.read_plan(project, plan_file)
    assert plan.title == "Alpha Plan"
    assert plan.status == "ready"
    assert "# body" in plan.body
    assert plan.history == []


def test_read_plan_missing(project):
    with pytest.raises(FileNotFoundError):
        plans.read_plan(project, "ghost")


def test_read_plan_validates_slug(project):
    with pytest.raises(ValueError):
        plans.read_plan(project, "../escape")


def test_manual_command_names_plan_path(project, plan_file):
    cmd = plans.manual_command(project, plan_file)
    assert f"{project.planning_dir}/{plan_file}.md" in cmd
    assert "claude -p" in cmd


def test_snapshot_and_diff(project):
    assert plans.snapshot(project) == {}
    write_plan(project, "a")
    before = plans.snapshot(project)
    assert set(before) == {"a"}
    write_plan(project, "b")
    write_plan(project, "a", "# changed to a longer body\n")
    after = plans.snapshot(project)
    assert plans.snapshot_diff(before, after) == ["a", "b"]
    assert plans.snapshot_diff(after, after) == []


def test_snapshot_missing_dir(project):
    project.planning_dir = "nope"
    assert plans.snapshot(project) == {}
