"""Unit tests for plan discovery + read + manual command + safe_slug."""

import pytest

from docket import core, tracker
from tests.conftest import write_plan


@pytest.mark.parametrize("slug", ["a", "a/b", "a-b.c_d", "feature/ITER_01"])
def test_safe_slug_accepts_valid(slug):
    assert core.safe_slug(slug) == slug


@pytest.mark.parametrize(
    "slug", ["", "/a", "a/", "a//b", "../x", "a/../b", "a/./b", "a b", "a\\b"]
)
def test_safe_slug_rejects_invalid(slug):
    with pytest.raises(ValueError):
        core.safe_slug(slug)


def test_list_plans_empty_when_no_planning_dir(tmp_path):
    p = core.Project(name="bare", path=str(tmp_path))
    assert core.list_plans(p) == []


def test_list_plans_discovers_nested_and_sorts(project):
    write_plan(project, "top", "---\ntitle: Top\n---\n")
    write_plan(project, "feature/ITER_01")
    tracker.set_status(project, "top", "implemented", trigger="manual")
    plans = core.list_plans(project)
    slugs = [p.slug for p in plans]
    assert "feature/ITER_01" in slugs
    assert slugs[0] == "top"  # sort is (status, slug): 'implemented' < 'ready'
    top = next(p for p in plans if p.slug == "top")
    assert top.title == "Top"
    assert top.status == "implemented"
    assert top.body == ""  # summaries carry no body


def test_list_plans_skips_directories_named_md(project):
    write_plan(project, "real")
    (core._planning_root(project) / "weird.md").mkdir()
    slugs = [p.slug for p in core.list_plans(project)]
    assert slugs == ["real"]


def test_list_plans_title_defaults_to_slug(project):
    write_plan(project, "untitled", "# no frontmatter\n")
    plan = core.list_plans(project)[0]
    assert plan.title == "untitled"


def test_read_plan_full_body_and_history(project):
    write_plan(project, "alpha", "---\ntitle: A\n---\n# hello\n")
    tracker.set_status(project, "alpha", "implemented", trigger="manual")
    plan = core.read_plan(project, "alpha")
    assert plan.title == "A"
    assert plan.status == "implemented"
    assert "# hello" in plan.body
    assert len(plan.history) == 1


def test_read_plan_missing_raises(project):
    with pytest.raises(FileNotFoundError, match="repo/ghost"):
        core.read_plan(project, "ghost")


def test_read_plan_invalid_slug_raises(project):
    with pytest.raises(ValueError):
        core.read_plan(project, "../escape")


def test_manual_command_contains_path_and_variant(project):
    cmd = core.manual_command(project, "feature/ITER_01")
    assert "claude -p < .agents_workspace/planning/feature/ITER_01.md" in cmd
    assert "# or:" in cmd


def test_manual_command_validates_slug(project):
    with pytest.raises(ValueError):
        core.manual_command(project, "..")


def test_project_lock_is_stable_per_path(project):
    a = core.project_lock(project.path)
    b = core.project_lock(project.path)
    assert a is b
    assert core.project_lock("/other") is not a
