"""What is installed: skills, subagents, MCP servers, and built-in tools.

Used names missing from the inventory still show on the dashboard, with source
``unknown``. The built-in lists come from ``reference.json`` when an export
fetched them; the hand-kept constants here are the fallback and can drift.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from claude_plugins import (
    load_plugin_agents,
    load_plugin_entries,
    load_plugin_skills,
    normalise_path,
)

BUILTIN_AGENTS = ("general-purpose", "Explore", "Plan", "statusline-setup", "claude-code-guide")
BUILTIN_TOOLS = (
    "Agent", "AskUserQuestion", "Bash", "Edit", "Glob", "Grep", "NotebookEdit", "Read",
    "Skill", "TodoWrite", "WebFetch", "WebSearch", "Write",
)


@dataclass(frozen=True)
class Item:
    """One installed thing and where it comes from.

    Attributes:
        name: As it appears in transcripts (``<plugin>:<member>`` for plugins).
        source: ``user``, ``project``, ``plugin:<plugin>``, or ``built-in``.
    """

    name: str
    source: str


@dataclass(frozen=True)
class Inventory:
    """Everything installed across the given Claude dirs and projects."""

    skills: list[Item]
    agents: list[Item]
    mcp_servers: list[Item]
    builtin_tools: list[str]


def _read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _server_names(config: dict[str, Any]) -> list[str]:
    servers = config.get("mcpServers")
    return list(servers) if isinstance(servers, dict) else []


def _add(items: dict[str, Item], name: str, source: str) -> None:
    """Keep the first source seen for a name."""
    items.setdefault(name, Item(name, source))


def load_inventory(
    claude_dirs: list[Path],
    project_paths: list[Path],
    builtin_tools: list[str] | None = None,
    builtin_agents: list[str] | None = None,
) -> Inventory:
    """Read what is installed for the given Claude dirs and project roots.

    Args:
        claude_dirs: Claude config dirs (``~/.claude`` by default elsewhere).
        project_paths: Project roots whose project/local plugins, ``.claude``
            skills and agents, and MCP servers count as installed.
        builtin_tools: Fetched built-in tool names; empty or ``None`` uses
            :data:`BUILTIN_TOOLS`.
        builtin_agents: Fetched built-in agent names; empty or ``None`` uses
            :data:`BUILTIN_AGENTS`. One also found as a file keeps the file's source.

    Returns:
        The :class:`Inventory`.
    """
    skills: dict[str, Item] = {}
    agents: dict[str, Item] = {}
    servers: dict[str, Item] = {}
    wanted = {normalise_path(str(p)) for p in project_paths}

    for claude_dir in claude_dirs:
        for m in load_plugin_skills(str(claude_dir)):
            _add(skills, m.name, "user")
        for m in load_plugin_agents(str(claude_dir)):
            _add(agents, m.name, "user")

        # User entries always count; project/local ones only for the given roots.
        installs: dict[str, str] = {}
        for entry in load_plugin_entries(claude_dir):
            if entry["scope"] == "user" or (
                entry["projectPath"] and normalise_path(entry["projectPath"]) in wanted
            ):
                installs.setdefault(entry["installPath"], entry["id"].split("@")[0])
        for install, plugin in installs.items():
            for m in load_plugin_skills(install):
                _add(skills, f"{plugin}:{m.name}", f"plugin:{plugin}")
            for m in load_plugin_agents(install):
                _add(agents, f"{plugin}:{m.name}", f"plugin:{plugin}")
            for name in _server_names(_read_json(Path(install) / ".mcp.json")):
                _add(servers, name, f"plugin:{plugin}")

        own = claude_dir / ".claude.json"
        config = _read_json(own if own.is_file() else Path.home() / ".claude.json")
        for name in _server_names(config):
            _add(servers, name, "user")
        projects = config.get("projects")
        if isinstance(projects, dict):
            for key, value in projects.items():
                if normalise_path(key) in wanted and isinstance(value, dict):
                    for name in _server_names(value):
                        _add(servers, name, "project")

    for root in project_paths:
        for m in load_plugin_skills(str(root / ".claude")):
            _add(skills, m.name, "project")
        for m in load_plugin_agents(str(root / ".claude")):
            _add(agents, m.name, "project")
        for name in _server_names(_read_json(root / ".mcp.json")):
            _add(servers, name, "project")

    for name in builtin_agents or BUILTIN_AGENTS:
        _add(agents, name, "built-in")
    return Inventory(
        list(skills.values()),
        list(agents.values()),
        list(servers.values()),
        list(builtin_tools or BUILTIN_TOOLS),
    )
