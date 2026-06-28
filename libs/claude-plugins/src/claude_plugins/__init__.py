"""claude-plugins: read Claude Code's installed plugins, skills, agents, hooks.

A dependency-free reader for Claude Code's on-disk plugin layout — the
``<claude_dir>/plugins/installed_plugins.json`` registry plus each plugin's
``skills/``, ``agents/`` and ``hooks/`` members. Shared by the
``claude-component-browser`` and ``per-project-plugin-toggler`` apps.
"""

from claude_plugins.members import (
    PluginHook,
    PluginMember,
    load_plugin_agents,
    load_plugin_hooks,
    load_plugin_skills,
    parse_frontmatter,
)
from claude_plugins.plugins import (
    claude_dir,
    load_installed_plugins,
    loose_bases,
    normalise_path,
    plugins_base,
)

__all__ = [
    "PluginHook",
    "PluginMember",
    "claude_dir",
    "load_installed_plugins",
    "load_plugin_agents",
    "load_plugin_hooks",
    "load_plugin_skills",
    "loose_bases",
    "normalise_path",
    "parse_frontmatter",
    "plugins_base",
]
