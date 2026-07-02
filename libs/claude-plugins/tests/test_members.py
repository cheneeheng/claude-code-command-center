"""Unit tests for member parsing: frontmatter, skills, agents, hooks (members.py)."""

from __future__ import annotations

import json
from pathlib import Path

from claude_plugins import (
    load_plugin_agents,
    load_plugin_hooks,
    load_plugin_skills,
    parse_frontmatter,
)


# ── parse_frontmatter ───────────────────────────────────────────────────────

def test_parse_frontmatter_inline_name_and_description(tmp_path: Path) -> None:
    md = tmp_path / "SKILL.md"
    md.write_text(
        '---\nname: "my-skill"\ndescription: A short one.\n---\nbody\n', encoding="utf-8"
    )
    assert parse_frontmatter(md) == ("my-skill", "A short one.")


def test_parse_frontmatter_block_scalar_description(tmp_path: Path) -> None:
    md = tmp_path / "SKILL.md"
    md.write_text(
        "---\nname: blk\ndescription: >-\n  line one\n  line two\n---\n", encoding="utf-8"
    )
    assert parse_frontmatter(md) == ("blk", "line one line two")


def test_parse_frontmatter_missing_name_uses_fallback(tmp_path: Path) -> None:
    md = tmp_path / "agent.md"
    md.write_text("---\ndescription: no name here\n---\n", encoding="utf-8")
    assert parse_frontmatter(md, fallback="agent") == ("agent", "no name here")


def test_parse_frontmatter_default_fallback_is_parent_dir(tmp_path: Path) -> None:
    folder = tmp_path / "some-skill"
    folder.mkdir()
    md = folder / "SKILL.md"
    md.write_text("---\ndescription: x\n---\n", encoding="utf-8")
    assert parse_frontmatter(md)[0] == "some-skill"


def test_parse_frontmatter_no_frontmatter_returns_fallback_and_empty(tmp_path: Path) -> None:
    md = tmp_path / "plain.md"
    md.write_text("just body, no frontmatter\n", encoding="utf-8")
    assert parse_frontmatter(md, fallback="fb") == ("fb", "")


def test_parse_frontmatter_unreadable_file_returns_fallback(tmp_path: Path) -> None:
    missing = tmp_path / "does-not-exist.md"
    assert parse_frontmatter(missing, fallback="fb") == ("fb", "")


def test_parse_frontmatter_frontmatter_without_description(tmp_path: Path) -> None:
    md = tmp_path / "SKILL.md"
    md.write_text("---\nname: only-name\n---\n", encoding="utf-8")
    assert parse_frontmatter(md) == ("only-name", "")


# ── load_plugin_skills ──────────────────────────────────────────────────────

def _make_skill(install: Path, folder: str, name: str, desc: str) -> None:
    d = install / "skills" / folder
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {desc}\n---\nbody\n", encoding="utf-8"
    )


def test_load_plugin_skills_empty_install_path() -> None:
    assert load_plugin_skills("") == []


def test_load_plugin_skills_no_skills_dir(tmp_path: Path) -> None:
    assert load_plugin_skills(str(tmp_path)) == []


def test_load_plugin_skills_reads_and_sorts_skipping_noise(tmp_path: Path) -> None:
    _make_skill(tmp_path, "beta", "beta-skill", "b")
    _make_skill(tmp_path, "alpha", "alpha-skill", "a")
    # A stray file and a skill folder without SKILL.md must both be skipped.
    (tmp_path / "skills" / "loose.txt").write_text("x", encoding="utf-8")
    (tmp_path / "skills" / "empty-folder").mkdir()
    skills = load_plugin_skills(str(tmp_path))
    assert [s.name for s in skills] == ["alpha-skill", "beta-skill"]
    assert skills[0].path.endswith("SKILL.md")


# ── load_plugin_agents ──────────────────────────────────────────────────────

def test_load_plugin_agents_empty_and_missing_dir(tmp_path: Path) -> None:
    assert load_plugin_agents("") == []
    assert load_plugin_agents(str(tmp_path)) == []


def test_load_plugin_agents_reads_flat_md_with_stem_fallback(tmp_path: Path) -> None:
    agents = tmp_path / "agents"
    agents.mkdir()
    (agents / "reviewer.md").write_text("---\ndescription: reviews\n---\n", encoding="utf-8")
    (agents / "named.md").write_text("---\nname: Fancy\ndescription: d\n---\n", encoding="utf-8")
    result = load_plugin_agents(str(tmp_path))
    by_name = {a.name for a in result}
    # reviewer.md has no `name:` -> falls back to the file stem.
    assert by_name == {"reviewer", "Fancy"}


# ── load_plugin_hooks ───────────────────────────────────────────────────────

def test_load_plugin_hooks_empty_and_missing(tmp_path: Path) -> None:
    assert load_plugin_hooks("") == []
    assert load_plugin_hooks(str(tmp_path)) == []


def test_load_plugin_hooks_invalid_json(tmp_path: Path) -> None:
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    (hooks / "hooks.json").write_text("{ broken", encoding="utf-8")
    assert load_plugin_hooks(str(tmp_path)) == []


def test_load_plugin_hooks_parses_groups_and_action_details(tmp_path: Path) -> None:
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    (hooks / "hooks.json").write_text(
        json.dumps(
            {
                "hooks": {
                    "PreToolUse": [
                        {
                            "matcher": "Bash",
                            "hooks": [
                                {"type": "command", "command": "echo hi"},
                                {"type": "command", "command": ["a", "b"]},
                                {"type": "http", "url": "https://x"},
                            ],
                        }
                    ],
                    "Stop": None,  # falsy group list -> skipped
                }
            }
        ),
        encoding="utf-8",
    )
    (group,) = load_plugin_hooks(str(tmp_path))
    assert group.event == "PreToolUse"
    assert group.matcher == "Bash"
    types = [a["type"] for a in group.actions]
    assert types == ["command", "command", "http"]
    # String command shows verbatim; non-string command and non-command are JSON-dumped.
    assert group.actions[0]["detail"] == "echo hi"
    assert group.actions[1]["detail"] == json.dumps(["a", "b"])
    assert group.actions[2]["detail"] == json.dumps({"url": "https://x"})
