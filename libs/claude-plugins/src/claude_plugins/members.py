"""Read a single installed plugin's members: skills, agents, and hooks.

Each plugin install directory may contain ``skills/<name>/SKILL.md`` files,
flat ``agents/<name>.md`` files, and a ``hooks/hooks.json``. These readers turn
that on-disk layout into typed records, with no third-party dependencies.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

__all__ = [
    "PluginHook",
    "PluginMember",
    "load_plugin_agents",
    "load_plugin_hooks",
    "load_plugin_skills",
    "parse_frontmatter",
]


@dataclass(frozen=True)
class PluginMember:
    """A skill or agent.

    Attributes:
        name: Display name from frontmatter (or a fallback).
        description: Description from frontmatter (may be empty).
        path: Source markdown file (a skill's ``SKILL.md`` or an agent's
            ``<name>.md``). Server-side detail — do not expose to untrusted
            clients.
        manual_only: ``disable-model-invocation: true`` in frontmatter — the
            model cannot invoke this skill; the user must call it. A skill
            concept: only :func:`load_plugin_skills` fills it, so agents keep
            the ``False`` default, as do skills that do not opt out.
    """

    name: str
    description: str
    path: str
    manual_only: bool = False


@dataclass(frozen=True)
class PluginHook:
    """One hook group from a plugin's ``hooks.json``.

    Attributes:
        event: The triggering event name (e.g. ``PreToolUse``).
        matcher: The matcher string for the group (may be empty).
        actions: One ``{"type", "detail"}`` dict per configured hook action.
    """

    event: str
    matcher: str
    actions: list[dict[str, str]]


def _unquote(value: str) -> str:
    """Strip one matching pair of surrounding quotes from a YAML inline scalar."""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _frontmatter(path: Path) -> str:
    """Return a markdown file's raw YAML frontmatter block (``""`` when absent)."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    return m.group(1) if m else ""


def _manual_only(fm: str) -> bool:
    """Return whether a frontmatter block sets ``disable-model-invocation: true``."""
    m = re.search(r"^disable-model-invocation:\s*(.+)$", fm, re.MULTILINE)
    return m is not None and _unquote(m.group(1).strip()).lower() == "true"


def _name_description(fm: str, fallback: str) -> tuple[str, str]:
    """Return ``(name, description)`` from a raw frontmatter block."""
    if not fm:
        return fallback, ""
    name_match = re.search(r"^name:\s*(.+)$", fm, re.MULTILINE)
    name = _unquote(name_match.group(1).strip()) if name_match else fallback
    block_match = re.search(
        r"^description:\s*(?:>-|>|[|][-]?)\s*\n((?:[ \t].+\n?)*)", fm, re.MULTILINE
    )
    if block_match:
        raw = block_match.group(1)
        description = " ".join(ln.strip() for ln in raw.splitlines() if ln.strip())
    else:
        # A plain (unmarked) scalar may still wrap onto more-indented lines; take
        # them all, or a long description shows up cut at its first line break.
        inline = re.search(r"^description:\s*(.+(?:\n[ \t]+\S.*)*)$", fm, re.MULTILINE)
        if inline:
            joined = " ".join(
                ln.strip() for ln in inline.group(1).splitlines() if ln.strip()
            )
            description = _unquote(joined)
        else:
            description = ""
    return name, description


def parse_frontmatter(path: Path, fallback: str = "") -> tuple[str, str]:
    """Return ``(name, description)`` from a markdown file's YAML frontmatter.

    Regex-based (no PyYAML); handles inline, wrapped (continued on more-indented
    lines) and block (``>-``/``>``/``|``) description scalars.

    Args:
        path: The markdown file to read.
        fallback: Name to use when the ``name`` key is absent. Defaults to the
            file's parent directory name (correct for ``skills/<name>/SKILL.md``);
            pass ``path.stem`` for flat ``agents/<name>.md`` files.

    Returns:
        ``(name, description)``; ``description`` is the empty string when absent.
    """
    if not fallback:
        fallback = path.parent.name
    return _name_description(_frontmatter(path), fallback)


def load_plugin_skills(install_path: str) -> list[PluginMember]:
    """Read every ``skills/<name>/SKILL.md`` under ``install_path``.

    Args:
        install_path: A plugin's install directory (empty string is allowed).

    Returns:
        Skills sorted by folder name; empty if ``install_path`` has no skills.
    """
    if not install_path:
        return []
    skills_dir = Path(install_path) / "skills"
    if not skills_dir.is_dir():
        return []
    members: list[PluginMember] = []
    for folder in sorted(skills_dir.iterdir()):
        if not folder.is_dir():
            continue
        skill_md = folder / "SKILL.md"
        if not skill_md.is_file():
            continue
        fm = _frontmatter(skill_md)
        name, description = _name_description(fm, folder.name)
        members.append(PluginMember(name, description, str(skill_md), _manual_only(fm)))
    return members


def load_plugin_agents(install_path: str) -> list[PluginMember]:
    """Read every flat ``agents/*.md`` file under ``install_path``.

    Args:
        install_path: A plugin's install directory (empty string is allowed).

    Returns:
        Agents sorted by filename; empty if ``install_path`` has no agents.
    """
    if not install_path:
        return []
    agents_dir = Path(install_path) / "agents"
    if not agents_dir.is_dir():
        return []
    members: list[PluginMember] = []
    for md_file in sorted(agents_dir.glob("*.md")):
        name, description = parse_frontmatter(md_file, fallback=md_file.stem)
        members.append(PluginMember(name, description, str(md_file)))
    return members


def _hook_detail(h: dict[str, object]) -> str:
    """Render one hook action to a compact, human-readable detail string."""
    # 'command' is the common case (and the documented example); show its string.
    if h.get("type") == "command":
        cmd = h.get("command", "")
        return cmd if isinstance(cmd, str) else json.dumps(cmd, ensure_ascii=False)
    # http / mcp_tool / prompt / agent: field names vary — dump the non-type
    # fields rather than inventing key names.
    return json.dumps({k: v for k, v in h.items() if k != "type"}, ensure_ascii=False)


def load_plugin_hooks(install_path: str) -> list[PluginHook]:
    """Read ``hooks/hooks.json`` under ``install_path`` into hook groups.

    Args:
        install_path: A plugin's install directory (empty string is allowed).

    Returns:
        One :class:`PluginHook` per matcher group, in file order; empty if the
        file is missing or unparseable.
    """
    if not install_path:
        return []
    path = Path(install_path) / "hooks" / "hooks.json"
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    result: list[PluginHook] = []
    for event, groups in (data.get("hooks") or {}).items():
        for group in groups or []:
            actions = [
                {"type": str(h.get("type", "")), "detail": _hook_detail(h)}
                for h in group.get("hooks", [])
            ]
            result.append(PluginHook(event, group.get("matcher", ""), actions))
    return result
